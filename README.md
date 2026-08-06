# AG Pay OpenClaw Playground

A local Docker playground for running an OpenClaw agent with the sibling AG Pay
plugin built, packaged, installed, enabled, and verified automatically.

The playground pins OpenClaw `2026.7.1-2`, matching the compatibility contract
in `../ag-plugin-openclaw`. Each image build runs the plugin's real
`pnpm build` and `pnpm pack` flow. A one-shot bootstrap service installs that
tarball through OpenClaw's managed `npm-pack:` path before the Gateway starts.
When the plugin source changes, rebuilding the image refreshes the installed
package while the OpenClaw state volume preserves configuration and
conversations.

The bootstrap also pins the external plugin id and the pinned release's default
bundled runtime plugins in `plugins.allow`, while keeping bundled provider
discovery in compatibility mode. This trusts the locally built `agpay` package
without disabling OpenClaw's normal local runtime surfaces. The bootstrap only
creates this allowlist when one is absent, so later operator edits are kept.

AG Pay is a supervised control plane. The plugin can request approval and,
when separately enabled, record a confirmed sandbox/external result. It does
not charge a card or execute a live payment.

## Workspace location

This repository must be cloned beside `ag-plugin-openclaw` under the base
workspace's `dev/` directory because its Docker build packages that sibling
source:

```bash
git clone https://github.com/AG-Pay-Labs/ag-openclaw-playground.git dev/ag-openclaw-playground
```

For a fresh installation of every repository, follow the
[AG Pay quick start](https://github.com/AG-Pay-Labs/ag-pay#quick-start).

## Requirements

- Docker with Compose v2;
- the sibling `../ag-plugin-openclaw` repository in its current workspace
  location;
- the AG Pay API and web app when you want to pair or exercise plugin tools;
- an OpenAI API key, or another model provider configured in OpenClaw, for
  actual agent turns.

The Gateway and Control UI are published only on host loopback. OpenClaw binds
to `lan` inside its container because Docker port forwarding requires a
non-loopback container listener.

## Start the playground

```bash
make init
make check
make smoke
make ps
make dashboard
```

`make init` creates a private `.env` once and generates a random Gateway token
without printing it. Add `OPENAI_API_KEY` to that file for automatic OpenAI
onboarding. OpenClaw stores an environment SecretRef in its configuration, not
the key itself. You may leave the key empty to inspect the Gateway and plugin,
then configure a provider through OpenClaw later. `make smoke` builds and starts
the Gateway, validates the plugin and SecretRefs, and checks Gateway RPC.

`make dashboard` prints the local Control UI URL. The default address is
`http://127.0.0.1:18789`. Because the Gateway token is SecretRef-managed,
OpenClaw intentionally does not embed it in the printed URL. If the UI prompts
for a token, copy `OPENCLAW_GATEWAY_TOKEN` privately from `.env`; do not paste
it into logs, chat, or a command argument.

## Connect the local AG Pay API

Start the base infrastructure, API, and web app through their owning
repositories. On Docker Desktop, the default playground settings forward
`127.0.0.1:8000` inside the OpenClaw container to
`host.docker.internal:8000` on the host. This loopback bridge preserves the
plugin rule that plain HTTP is allowed only to an explicit loopback address.
Do not weaken that plugin rule to make container networking easier.

On native Linux Docker, a host process bound only to `127.0.0.1` is usually not
reachable through the host-gateway address. For local Linux development, bind
the API to a carefully firewalled container-reachable host interface. For a
remote development API, set `AGPAY_PROXY_ENABLED=0` and use an HTTPS
`AGPAY_API_URL` instead.

## Pair the OpenClaw runtime

Create or re-pair an agent in the AG Pay web app and copy its one-time
`pair_...` token. Then run:

```bash
make pair
```

The plugin asks for the token at a hidden prompt. The token is never placed in
a command argument. The resulting `agt_...` bearer credential is written with
private permissions inside the persistent OpenClaw state volume, referenced
through a file-backed SecretRef, and never printed. `make pair` restarts the
Gateway so the heartbeat and tools use the new reference.

To intentionally replace an existing pairing:

```bash
make re-pair
```

## Verify the live integration

```bash
make smoke
```

The smoke check builds and starts the stack, inspects the live `agpay` plugin
runtime, audits SecretRefs, and requires a readable Gateway RPC endpoint. It
proves that these plugin surfaces are registered; it does not prove pairing,
API heartbeat, or a completed purchase:

- `agpay_request_purchase`;
- `agpay_get_purchase_request`;
- `agpay_record_purchase_result` (kept gated by
  `allowSandboxCompletion: false` by default);
- `openclaw agpay pair`;
- the AG Pay heartbeat service.

The playground adds only the request and read tools to the default tool
profile. Recording a result stays unavailable unless an operator explicitly
enables both the tool policy and `allowSandboxCompletion`; even then it only
records a confirmed sandbox/external result.

Useful focused commands:

```bash
make plugin-inspect
make secrets-audit
make status
make logs
make ps
```

## Rebuild after plugin changes

Run `make up` after editing `../ag-plugin-openclaw`. Compose rebuilds the
package layer, the bootstrap compares the packaged artifact digest with the
installed digest, and OpenClaw replaces the managed plugin before starting the
Gateway.

`make down` stops the containers without deleting named volumes. This project
intentionally has no automatic volume-deletion target because those volumes
contain conversations, provider configuration, and the paired AG Pay token.
