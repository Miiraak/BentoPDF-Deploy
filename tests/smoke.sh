#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Smoke test failed at line $LINENO" >&2' ERR

IMAGE="${1:?Usage: bash tests/smoke.sh IMAGE [DOCUMENT_ROOT]}"
VOLUMES=()
if [[ -n "${2:-}" ]]; then
    VOLUMES=(-v "$2:/usr/share/nginx/html:ro")
fi
WORKDIR=$(mktemp -d)
CONTAINER=""
cleanup() {
    if [[ -n "$CONTAINER" ]]; then
        docker rm -f "$CONTAINER" >/dev/null
    fi
    rm -rf -- "$WORKDIR"
}
trap cleanup EXIT

openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
    >/dev/null 2>&1

CONTAINER=$(docker run -d --health-interval=1s --health-start-period=1s \
    -p 127.0.0.1::80 -p 127.0.0.1::443 \
    -v "$WORKDIR:/etc/nginx/certs:ro" "${VOLUMES[@]}" "$IMAGE")
HTTP_PORT=$(docker inspect -f '{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostPort}}' "$CONTAINER")
TLS_PORT=$(docker inspect -f '{{(index (index .NetworkSettings.Ports "443/tcp") 0).HostPort}}' "$CONTAINER")

for ((attempt = 0; attempt < 60; attempt++)); do
    if [[ "$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER")" == healthy ]]; then
        break
    fi
    sleep 1
done
if [[ "$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER")" != healthy ]]; then
    docker logs "$CONTAINER" >&2
    docker inspect -f '{{json .State.Health}}' "$CONTAINER" >&2
    exit 1
fi
docker exec "$CONTAINER" nginx -t

check_headers() {
    local path="$1" status="$2"
    curl -ksS --max-time 15 -D "$WORKDIR/headers" -o /dev/null \
        "https://127.0.0.1:$TLS_PORT$path"
    tr -d '\r' < "$WORKDIR/headers" > "$WORKDIR/normalized"
    grep -Eq "^HTTP/1.1 $status " "$WORKDIR/normalized"
    grep -Fqi 'Strict-Transport-Security: max-age=31536000; includeSubDomains' "$WORKDIR/normalized"
    grep -Fqi 'X-Content-Type-Options: nosniff' "$WORKDIR/normalized"
    grep -Fqi 'Cross-Origin-Embedder-Policy: require-corp' "$WORKDIR/normalized"
    grep -Fqi 'Cross-Origin-Opener-Policy: same-origin' "$WORKDIR/normalized"
    grep -Fqi 'Cross-Origin-Resource-Policy: cross-origin' "$WORKDIR/normalized"
}

for path in / /index.html /fr/index.html /config.json \
    /wasm/tesseract/worker.min.js /libreoffice-wasm/soffice.wasm.gz \
    /libreoffice-wasm/soffice.data.gz; do
    check_headers "$path" 200
    if [[ "$path" == /libreoffice-wasm/*.gz ]]; then
        grep -Fqi 'Content-Encoding: gzip' "$WORKDIR/normalized"
    fi
    if [[ "$path" == /libreoffice-wasm/soffice.wasm.gz ]]; then
        grep -Fqi 'Content-Type: application/wasm' "$WORKDIR/normalized"
    fi
done
check_headers /wasm/not-found.wasm 404
curl -kfsS --max-time 15 "https://127.0.0.1:$TLS_PORT/config.json" \
    | grep -Fx '{"disabledTools":[],"editorDisabledCategories":[]}'

curl -fsS --max-time 15 -D "$WORKDIR/redirect" -o /dev/null \
    -H 'Host: example.test:8080' "http://127.0.0.1:$HTTP_PORT/path?x=1"
grep -Fq '301 Moved Permanently' "$WORKDIR/redirect"
grep -Fq 'Location: https://example.test:443/path?x=1' "$WORKDIR/redirect"

docker rm -f "$CONTAINER" >/dev/null
CONTAINER=""
CONTAINER=$(docker run -d -e HTTPS_PORT=8443 \
    -p 127.0.0.1::80 -v "$WORKDIR:/etc/nginx/certs:ro" "${VOLUMES[@]}" "$IMAGE")
HTTP_PORT=$(docker inspect -f '{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostPort}}' "$CONTAINER")
for ((attempt = 0; attempt < 30; attempt++)); do
    if curl -fsS --max-time 2 -D "$WORKDIR/redirect" -o /dev/null \
        -H 'Host: example.test:8080' "http://127.0.0.1:$HTTP_PORT/path?x=1"; then
        break
    fi
    sleep 1
done
grep -Fq 'Location: https://example.test:8443/path?x=1' "$WORKDIR/redirect"
echo "HTTPS, healthcheck, routes, headers, WASM and custom port: OK"
