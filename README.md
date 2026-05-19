# bearer-proxy

A minimal nginx reverse proxy that authenticates requests using bearer tokens.

## API Keys

One key per line. Lines starting with `#` and blank lines are ignored. Both LF and CRLF line endings are supported.

```
# api_keys.txt
sk-alice
sk-bob
```

Keys are loaded once at startup. **Rotating keys requires restarting the container** — there is no hot-reload.

## Streaming

Streaming responses (SSE, chunked transfer) are fully supported. Response buffering is disabled and connections use HTTP/1.1 keep-alive. Use `PROXY_READ_TIMEOUT` and `PROXY_SEND_TIMEOUT` to tune for long-running or slow-streaming upstreams.

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `UPSTREAM` | ✅ | — | Backend URL to proxy to |
| `PORT` | ❌ | `80` | Port to listen on |
| `PROXY_READ_TIMEOUT` | ❌ | `300s` | Timeout between reads from upstream |
| `PROXY_SEND_TIMEOUT` | ❌ | `60s` | Timeout for sending requests to upstream |
| `CLIENT_MAX_BODY_SIZE` | ❌ | `128m` | Max request body size |
| `API_KEYS_FILE` | ❌ | `/run/secrets/api_keys` | Path to the file containing API keys |

## Deployment Scenarios

### 1. Cloudflare Tunnel

The recommended public deployment. Cloudflare terminates TLS and handles per-client rate limiting at the edge. The proxy receives traffic from the local `cloudflared` daemon.

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=${TUNNEL_TOKEN}

  proxy:
    image: ghcr.io/rafaelkallis/bearer-proxy:latest
    secrets:
      - api_keys
    environment:
      - UPSTREAM=http://your-backend:8080

  your-backend:
    image: your-backend

secrets:
  api_keys:
    file: ./api_keys.txt
```

> `X-Forwarded-Proto: https` is passed through from Cloudflare. `CF-Connecting-IP` (the real client IP) is forwarded to the upstream unchanged. `X-Real-IP` will reflect the `cloudflared` daemon's IP, not the real client — use `CF-Connecting-IP` upstream if you need the real IP.

### 2. Host-exposed (HTTP)

Direct port mapping to the host. Suitable for internal networks or when a separate TLS terminator (Traefik, Caddy) sits in front on the same host.

```yaml
services:
  proxy:
    image: ghcr.io/rafaelkallis/bearer-proxy:latest
    ports:
      - "8000:80"
    secrets:
      - api_keys
    environment:
      - UPSTREAM=http://your-backend:8080

  your-backend:
    image: your-backend

secrets:
  api_keys:
    file: ./api_keys.txt
```

> `X-Forwarded-Proto` is omitted when there is no upstream proxy (nginx drops empty headers). `X-Real-IP` and `X-Forwarded-For` reflect the real client IP.

### 3. Service-to-service (Docker network)

The proxy sits inside a Docker network, consumed by another service. No port is exposed to the host.

```yaml
services:
  proxy:
    image: ghcr.io/rafaelkallis/bearer-proxy:latest
    secrets:
      - api_keys
    environment:
      - UPSTREAM=http://your-backend:8080

  your-backend:
    image: your-backend

  your-client:
    image: your-client
    environment:
      - API_BASE_URL=http://proxy
      - API_KEY=sk-your-client

secrets:
  api_keys:
    file: ./api_keys.txt
```

> All traffic stays on the Docker network. `X-Forwarded-For` and `X-Real-IP` reflect the calling service's Docker network IP.

## Rate Limiting

This proxy does **not** implement rate limiting. The reasons depend on the deployment scenario:

- **Cloudflare Tunnel** (recommended): all traffic arrives from the local `cloudflared` daemon, so `$remote_addr` is always the daemon's IP — not the real client's. A per-IP rate limit would bucket every real client together, making it either useless or a self-inflicted denial of service. Cloudflare's edge rate limiting operates on the real client IP and is the right place to enforce this.
- **Service-to-service (Docker network)**: the calling service is a known, trusted peer. Rate limiting a trusted internal service adds operational friction with little security benefit.
- **Host-exposed (HTTP)**: if you expose the proxy directly to untrusted clients, consider putting a proper reverse proxy (Traefik, Caddy, Cloudflare) in front and applying rate limits there.

## Security

This proxy does **not** terminate TLS. Bearer tokens will be transmitted in plaintext unless this container runs behind a TLS terminator (e.g. Traefik, Caddy, or a cloud load balancer). Do not expose it directly on the internet without TLS.

The `Authorization` header is **stripped** before the request is forwarded to the upstream. The upstream never sees the bearer token. If your upstream requires its own authentication, set it via a separate header or embed credentials in the `UPSTREAM` URL.