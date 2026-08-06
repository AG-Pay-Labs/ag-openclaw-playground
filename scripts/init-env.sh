#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
example_path="$project_dir/.env.example"
env_path="$project_dir/.env"

if [ -e "$env_path" ]; then
  printf '%s\n' ".env already exists; leaving it unchanged"
  exit 0
fi

if command -v openssl >/dev/null 2>&1; then
  gateway_token=$(openssl rand -hex 32)
else
  gateway_token=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
fi

umask 077
temporary_path=$(mktemp "$project_dir/.env.tmp.XXXXXX")
cleanup() {
  rm -f "$temporary_path"
}
trap cleanup EXIT HUP INT TERM

awk -v token="$gateway_token" '
  /^OPENCLAW_GATEWAY_TOKEN=$/ {
    print "OPENCLAW_GATEWAY_TOKEN=" token
    next
  }
  { print }
' "$example_path" > "$temporary_path"

chmod 0600 "$temporary_path"
mv "$temporary_path" "$env_path"
trap - EXIT HUP INT TERM

printf '%s\n' "Created private .env with a generated Gateway token"
printf '%s\n' "Add OPENAI_API_KEY to .env before make up for a usable model-backed agent"
