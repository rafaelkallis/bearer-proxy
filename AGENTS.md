# bearer-proxy

Minimal nginx reverse proxy that authenticates requests using bearer tokens before forwarding to an upstream.

## Architecture

| File | Role |
|------|------|
| `Dockerfile` | Builds the image from `nginx:alpine`; sets env defaults; registers the startup script |
| `nginx.conf.template` | Nginx config template; rendered at container start via `envsubst` |
| `generate-api-keys-map.sh` | Startup script (`docker-entrypoint.d`) that reads `API_KEYS_FILE` and writes `/etc/nginx/api_keys.map` |

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

**API key map**: `generate-api-keys-map.sh` regex-escapes each key and emits a case-insensitive nginx map entry matching `Bearer <key>`. The map file is written to `/etc/nginx/api_keys.map` with mode `600`. Included by `nginx.conf.template` via `include /etc/nginx/api_keys.map`.

**No hot-reload**: keys are loaded once at startup. Rotating keys requires restarting the container.

**Authorization header is stripped**: nginx removes the `Authorization` header before forwarding. Upstream services never see the bearer token.

**Health check**: a separate server block listens on port `9494` at `/health`. This port is internal only and must not be exposed in production.

**No TLS termination**: the proxy speaks plain HTTP. TLS must be handled upstream (Cloudflare Tunnel, Traefik, Caddy, etc.).

**No rate limiting**: intentionally absent. See README.md § Rate Limiting for the reasoning per deployment scenario.

## Deployment

See README.md for Docker Compose examples covering Cloudflare Tunnel, host-exposed HTTP, and service-to-service setups.
