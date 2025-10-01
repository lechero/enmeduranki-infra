# Repository Guidelines

## Project Structure & Module Organization
- `proxy/` hosts the Traefik reverse proxy stack (`docker-compose.yml`, `traefik.yml`, and the persisted `acme.json`). Update these files when changing ingress rules or TLS settings.
- `apps/` contains service-specific Compose bundles. The `myapp/` example runs the `traefik/whoami` container and demonstrates the routing labels expected for production workloads.
- `install.sh` bootstraps Docker, UFW, and the shared `proxy` network on fresh Debian 13 hosts. Mirror its conventions when adding additional provisioning scripts.

## Build, Test, and Development Commands
- Bring up the proxy: `docker compose -f proxy/docker-compose.yml up -d` (creates Traefik and listens on :80/:443).
- Launch an app stack: `docker compose -f apps/<service>/docker-compose.yml up -d` (services must attach to the external `proxy` network).
- Tear down a stack: append `down` to the commands above, or pass `--remove-orphans` during iterative changes to prune retired containers.

## Coding Style & Naming Conventions
- Prefer YAML with two-space indentation; order labels, environment keys, and volumes alphabetically to ease diffs.
- Use lower-case service keys in Compose files (`whoami`, `traefik`) and hyphenated container names (`myapp-whoami`) to match existing patterns.
- Bash scripts should enable `set -euo pipefail`, log major actions with `[INFO]/[ERROR]`, and avoid silent fallbacks.

## Testing Guidelines
- Validate Compose syntax before deploying: `docker compose -f <path>/docker-compose.yml config -q`.
- Smoke-test Traefik changes locally with `docker compose -f proxy/docker-compose.yml up` and hit `http://localhost` to confirm routing.
- Run `shellcheck install.sh` for any shell updates; block merges that introduce warnings unless justified in review.

## Commit & Pull Request Guidelines
- Write imperative, present-tense summaries (e.g., `Add whoami example stack`) and keep the first line under 72 characters.
- Group infrastructure tweaks by concern (proxy vs. app) and note the affected Compose file paths in the body.
- Pull requests should describe rollout steps, reference tracked tickets, and capture any required DNS or TLS follow-up.

## Security & Configuration Tips
- Never commit live `acme.json` data; use the empty placeholder checked into `proxy/` and populate secrets at runtime.
- When adding services, confirm labels restrict exposure (`traefik.enable=true` on specific routers) and avoid leaking internal endpoints to the public edge.
