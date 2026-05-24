# syntax=docker/dockerfile:1

ARG BASE_IMAGE="nginx:alpine"
FROM ${BASE_IMAGE}

LABEL maintainer="Rafael Kallis <rk@rafaelkallis.com>"

COPY generate-api-keys-map.sh /docker-entrypoint.d/10-generate-api-keys-map.sh
COPY nginx.conf.template /etc/nginx/templates/default.conf.template

RUN chmod +x /docker-entrypoint.d/10-generate-api-keys-map.sh

ENV NGINX_ENVSUBST_FILTER="PORT|UPSTREAM|PROXY_READ_TIMEOUT|PROXY_SEND_TIMEOUT|CLIENT_MAX_BODY_SIZE"

ENV UPSTREAM=""
ENV PORT="80"
ENV PROXY_SEND_TIMEOUT="60s"
ENV PROXY_READ_TIMEOUT="300s"
ENV CLIENT_MAX_BODY_SIZE="128m"
ENV API_KEYS_FILE="/run/secrets/api_keys"

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:9494/health || exit 1