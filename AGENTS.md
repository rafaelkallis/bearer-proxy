# bearer-proxy

Minimal nginx reverse proxy that authenticates requests using bearer tokens before forwarding to an upstream.

## Architecture

| File | Role |
|------|------|
| `Dockerfile` | Builds the image from `nginx:alpine`; sets env defaults; registers the startup script |
| `nginx.conf.template` | Nginx config template; rendered at container start via `envsubst` |
| `generate-api-keys-map.sh` | Startup script (`docker-entrypoint.d`) that reads `API_KEYS_FILE` and writes `/etc/nginx/api_keys.map` |
| `.github/workflows/publish.yml` | Scheduled pipeline that builds and publishes multi-arch images to `ghcr.io/rafaelkallis/bearer-proxy` |
| `tests/unit.sh` | Unit tests for `generate-api-keys-map.sh`; plain sh, run directly on the CI runner (no Docker) |
| `tests/integration.sh` | Integration tests; spins up the container + mock upstream and asserts HTTP behavior via curl |
| `tests/docker-compose.test.yml` | Compose file for integration tests; uses `traefik/whoami` as the mock upstream |
| `tests/fixtures/api_keys` | Test API key fixture used by the integration tests |

**Request flow**: incoming request → nginx checks `Authorization` header against `/etc/nginx/api_keys.map` → 401 if invalid → proxy to `$UPSTREAM` with `Authorization` stripped.

## Build

```sh
docker build .
```

No external dependencies beyond Docker.

## Configuration

Environment variables (see README.md for full table):

- `UPSTREAM` — required; backend URL to proxy to
- `PORT` — default `80`; main proxy listen port
- `API_KEYS_FILE` — default `/run/secrets/api_keys`; path to the newline-delimited key file
- `PROXY_READ_TIMEOUT`, `PROXY_SEND_TIMEOUT`, `CLIENT_MAX_BODY_SIZE` — tuning knobs

API keys file format: one key per line; lines starting with `#` and blank lines are ignored; LF and CRLF both supported.

## Conventions

**`nginx.conf.template` envsubst scope**: `NGINX_ENVSUBST_FILTER` is set to `PORT|UPSTREAM|PROXY_READ_TIMEOUT|PROXY_SEND_TIMEOUT|CLIENT_MAX_BODY_SIZE`. Only those five variables are substituted. Any other `${VAR}` in the template (e.g. nginx variables like `$host`) is left untouched. When adding new template variables, update `NGINX_ENVSUBST_FILTER` in the Dockerfile.

**API key map**: `generate-api-keys-map.sh` regex-escapes each key and emits a case-insensitive nginx map entry matching `Bearer <key>`. The map file path defaults to `/etc/nginx/api_keys.map` and can be overridden via `API_KEYS_MAP_FILE` (used by the test suite). Mode `600`. Included by `nginx.conf.template` via `include /etc/nginx/api_keys.map`.

**No hot-reload**: keys are loaded once at startup. Rotating keys requires restarting the container.

**Authorization header is stripped**: nginx removes the `Authorization` header before forwarding. Upstream services never see the bearer token.

**Health check**: a separate server block listens on port `9494` at `/health`. This port is internal only and must not be exposed in production.

**No TLS termination**: the proxy speaks plain HTTP. TLS must be handled upstream (Cloudflare Tunnel, Traefik, Caddy, etc.).

**No rate limiting**: intentionally absent. See README.md § Rate Limiting for the reasoning per deployment scenario.

## Deployment

See README.md for Docker Compose examples covering Cloudflare Tunnel, host-exposed HTTP, and service-to-service setups.

## Publish Pipeline

`.github/workflows/publish.yml` runs daily at 02:00 UTC (and on `workflow_dispatch`).

**Tag discovery**: the `discover` job fetches `OFFICIAL_IMAGES_URL` (the `docker-library/official-images` library file for nginx — the same source Docker Hub uses) and parses all `Tags:` blocks into alias clusters. For each entry in `WATCHED_TAGS`, it finds the cluster containing that tag and deduplicates (e.g. `latest` and `trixie` resolve to the same cluster → one build).

**Build**: the `build` job runs one matrix entry per cluster. Each entry: (1) builds a `linux/amd64` image with `BASE_IMAGE=nginx:<watched_tag>` and loads it locally as `bearer-proxy:test`; (2) runs `tests/unit.sh` and `tests/integration.sh` against it; (3) if tests pass, builds the final multi-arch image (`linux/amd64`, `linux/arm64`) and pushes it to GHCR tagged with every alias in the cluster. Tests always run against the exact base image about to be published.

**To change watched tags**: edit the two `'latest alpine trixie'` literals in the workflow — the `workflow_dispatch` input `default:` (for UI) and the `WATCHED_TAGS` env fallback (for scheduled runs). Both must stay in sync.

**Auth**: `GITHUB_TOKEN` with `packages: write` permission — no additional secrets needed.
