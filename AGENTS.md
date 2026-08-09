# AG Pay OpenClaw playground development guide

## Repository boundary

This is an independently versioned child repository. It owns only the local
Docker playground that runs OpenClaw with the AG Pay plugin. Do not stage it in
the parent `ag-pay` repository or turn it into a submodule.

The sibling `../ag-plugin-openclaw` repository owns the plugin source and
package metadata. The playground may build and consume that source, but must
not duplicate or silently patch plugin behavior. The versioned API in
`../ag-pay-platform` remains the business and authorization boundary.

## Product and security invariants

- The plugin requests supervised approval and receives only sanitized checkout
  outcomes. For a configured managed proposal, the sibling AG Pay platform's
  trusted worker may execute checkout; the playground and OpenClaw runtime do
  not receive Browserbase, issuer, PAN, CVC, or merchant-password secrets.
- Never accept, store, log, or return raw PAN, CVC, PIN, or 3-D Secure secrets.
- Never commit `.env`, OpenClaw state, model-provider keys, Gateway tokens,
  pairing tokens, or AG Pay agent bearer tokens.
- Pair through the plugin-owned hidden prompt. Do not put `pair_...` tokens in
  command arguments, shell history, Compose files, or logs.
- Keep the AG Pay `agt_...` bearer token in the private OpenClaw secret file and
  reference it through OpenClaw SecretRef configuration.
- Bind the host Gateway port to loopback. Container `lan` binding is only for
  Docker port forwarding and must not expose the playground on the host LAN.
- Keep sandbox result recording disabled by default. Enabling it only records a
  confirmed legacy external/sandbox result; it never initiates managed payment.
- Keep Browserbase and issuer configuration in `ag-pay-platform`. Never add
  those secrets to this repository's `.env`, Compose services, or OpenClaw
  configuration.

## Required checks

Run these from this repository:

```bash
make check
make smoke
make ps
```

`make smoke` includes the image build and requires Docker, a configured `.env`,
and a healthy Gateway. A reachable AG Pay API and paired agent are required for
heartbeat/tool calls, but not for proving that the plugin package loads into
OpenClaw. The smoke test never initiates or proves a purchase.
