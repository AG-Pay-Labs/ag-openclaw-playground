#!/bin/sh

set -eu
umask 077

state_dir=${OPENCLAW_STATE_DIR:-/home/node/.openclaw}
config_path=${OPENCLAW_CONFIG_PATH:-$state_dir/openclaw.json}
workspace_dir="$state_dir/workspace"
secret_dir="$state_dir/secrets"
agent_token_path="$secret_dir/agpay-agent-token"
plugin_archive=/opt/agpay-plugin/agpay-openclaw-plugin.tgz
plugin_digest_path="$state_dir/.agpay-plugin.sha256"
openai_marker_path="$state_dir/.openai-secret-ref-configured"

run_openclaw() {
  node /app/dist/index.js "$@"
}

require_gateway_token() {
  if [ -z "${PLAYGROUND_GATEWAY_TOKEN:-}" ]; then
    printf '%s\n' "OPENCLAW_GATEWAY_TOKEN is empty; run make init or configure .env" >&2
    exit 1
  fi
}

ensure_state_directories() {
  mkdir -p "$state_dir" "$workspace_dir" "$secret_dir"
  chmod 0700 "$state_dir" "$secret_dir"
}

onboard_without_model() {
  run_openclaw onboard \
    --non-interactive \
    --accept-risk \
    --mode local \
    --auth-choice skip \
    --gateway-port 18789 \
    --gateway-bind lan \
    --gateway-auth token \
    --gateway-token-ref-env PLAYGROUND_GATEWAY_TOKEN \
    --no-install-daemon \
    --skip-channels \
    --skip-skills \
    --skip-search \
    --skip-hooks \
    --skip-health \
    --skip-ui \
    --suppress-gateway-token-output
}

onboard_with_openai() {
  run_openclaw onboard \
    --non-interactive \
    --accept-risk \
    --mode local \
    --auth-choice openai-api-key \
    --secret-input-mode ref \
    --gateway-port 18789 \
    --gateway-bind lan \
    --gateway-auth token \
    --gateway-token-ref-env PLAYGROUND_GATEWAY_TOKEN \
    --no-install-daemon \
    --skip-channels \
    --skip-skills \
    --skip-search \
    --skip-hooks \
    --skip-health \
    --skip-ui \
    --suppress-gateway-token-output
  : > "$openai_marker_path"
}

ensure_onboarded() {
  if [ ! -s "$config_path" ]; then
    if [ -n "${OPENAI_API_KEY:-}" ]; then
      onboard_with_openai
    else
      onboard_without_model
    fi
    return
  fi

  if [ -n "${OPENAI_API_KEY:-}" ] && [ ! -f "$openai_marker_path" ]; then
    onboard_with_openai
  fi
}

configure_gateway_token_ref() {
  run_openclaw config set gateway.auth.mode token
  run_openclaw config set gateway.auth.token \
    --ref-source env \
    --ref-provider default \
    --ref-id PLAYGROUND_GATEWAY_TOKEN
}

plugin_digest() {
  node -e '
    const crypto = require("node:crypto");
    const fs = require("node:fs");
    const path = process.argv[1];
    const hash = crypto.createHash("sha256");
    hash.update(fs.readFileSync(path));
    process.stdout.write(hash.digest("hex"));
  ' "$plugin_archive"
}

ensure_plugin_installed() {
  expected_digest=$(plugin_digest)
  installed_digest=""
  if [ -f "$plugin_digest_path" ]; then
    installed_digest=$(sed -n '1p' "$plugin_digest_path")
  fi

  if [ "$expected_digest" != "$installed_digest" ] \
    || ! run_openclaw plugins inspect agpay --json >/dev/null 2>&1; then
    run_openclaw plugins install "npm-pack:$plugin_archive" --force
    printf '%s\n' "$expected_digest" > "$plugin_digest_path"
  fi
}

config_exists() {
  run_openclaw config get "$1" >/dev/null 2>&1
}

patch_default_checkout_pair() {
  node -e '
    const [adapter, checkoutUrl] = process.argv.slice(1);
    const enabled = adapter.length > 0 && checkoutUrl.length > 0;
    process.stdout.write(JSON.stringify({
      plugins: {
        entries: {
          agpay: {
            config: {
              defaultCheckoutAdapter: enabled ? adapter : null,
              defaultCheckoutUrl: enabled ? checkoutUrl : null,
            },
          },
        },
      },
    }));
  ' "$1" "$2" | run_openclaw config patch --stdin
}

configure_agent_token_ref() {
  run_openclaw config set secrets.providers.agpay \
    --provider-source file \
    --provider-path "$agent_token_path" \
    --provider-mode singleValue
  run_openclaw config set plugins.entries.agpay.config.agentToken \
    --ref-source file \
    --ref-provider agpay \
    --ref-id value
}

configure_plugin() {
  run_openclaw config set plugins.entries.agpay.enabled true --strict-json
  run_openclaw config set plugins.entries.agpay.config.apiUrl \
    "${AGPAY_API_URL:-http://127.0.0.1:8000}"

  default_checkout_adapter=${AGPAY_DEFAULT_CHECKOUT_ADAPTER:-}
  default_checkout_url=${AGPAY_DEFAULT_CHECKOUT_URL:-}
  if [ -n "$default_checkout_adapter" ] && [ -n "$default_checkout_url" ]; then
    patch_default_checkout_pair "$default_checkout_adapter" "$default_checkout_url"
  elif [ -n "$default_checkout_adapter" ] || [ -n "$default_checkout_url" ]; then
    printf '%s\n' \
      "AGPAY_DEFAULT_CHECKOUT_ADAPTER and AGPAY_DEFAULT_CHECKOUT_URL must be configured together" >&2
    exit 1
  else
    if config_exists plugins.entries.agpay.config.defaultCheckoutAdapter \
      || config_exists plugins.entries.agpay.config.defaultCheckoutUrl; then
      patch_default_checkout_pair "" ""
    fi
  fi

  if ! config_exists plugins.allow; then
    run_openclaw config set plugins.allow \
      '["agpay","browser","canvas","device-pair","file-transfer","memory-core","ollama","phone-control","talk-voice"]' \
      --strict-json
    run_openclaw config set plugins.bundledDiscovery compat
  fi

  if ! config_exists plugins.entries.agpay.config.allowSandboxCompletion; then
    run_openclaw config set \
      plugins.entries.agpay.config.allowSandboxCompletion false --strict-json
  fi

  if ! config_exists tools.allow && ! config_exists tools.alsoAllow; then
    run_openclaw config set tools.alsoAllow \
      '["agpay_request_purchase","agpay_get_purchase_request"]' \
      --strict-json
  fi

  if [ -f "$agent_token_path" ]; then
    configure_agent_token_ref
  fi

  host_port=${PLAYGROUND_HOST_PORT:-18789}
  run_openclaw config set gateway.controlUi.allowedOrigins \
    "[\"http://127.0.0.1:$host_port\",\"http://localhost:$host_port\"]" \
    --strict-json
  run_openclaw config validate
}

bootstrap() {
  require_gateway_token
  ensure_state_directories
  ensure_onboarded
  configure_gateway_token_ref
  ensure_plugin_installed
  configure_plugin
}

pair_agent() {
  ensure_state_directories

  force_pairing=0
  for argument in "$@"; do
    if [ "$argument" = "--force" ]; then
      force_pairing=1
    fi
  done

  if [ -f "$agent_token_path" ] && [ "$force_pairing" -eq 0 ]; then
    configure_agent_token_ref
    run_openclaw config validate
    printf '%s\n' \
      "AG Pay is already paired; kept the existing private credential. Use make re-pair only to replace it."
    return
  fi

  run_openclaw agpay pair \
    --api-url "${AGPAY_API_URL:-http://127.0.0.1:8000}" \
    --output "$agent_token_path" \
    "$@"
  configure_agent_token_ref
  run_openclaw config validate
  printf '%s\n' "AG Pay pairing stored as a private file-backed SecretRef"
}

start_gateway() {
  require_gateway_token
  if [ "${AGPAY_PROXY_ENABLED:-1}" = "1" ]; then
    printf '%s\n' \
      "Starting AG Pay loopback bridge to ${AGPAY_HOST:-host.docker.internal}:${AGPAY_HOST_PORT:-8000}"
    socat \
      "TCP-LISTEN:8000,bind=127.0.0.1,reuseaddr,fork" \
      "TCP:${AGPAY_HOST:-host.docker.internal}:${AGPAY_HOST_PORT:-8000}" &
  fi
  exec node /app/dist/index.js gateway --bind lan --port 18789 "$@"
}

command=${1:-gateway}
if [ "$#" -gt 0 ]; then
  shift
fi

case "$command" in
  bootstrap)
    bootstrap "$@"
    ;;
  gateway)
    start_gateway "$@"
    ;;
  pair)
    pair_agent "$@"
    ;;
  *)
    printf '%s\n' "Unknown playground command: $command" >&2
    exit 2
    ;;
esac
