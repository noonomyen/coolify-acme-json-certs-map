#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test data - base64("TEST_CERT_0"), base64("TEST_KEY_0"), etc.
DOMAIN="example.com"
CERT_0="VEVTVF9DRVJUXzA="
KEY_0="VEVTVF9LRVlfMA=="
CERT_1="VEVTVF9DRVJUXzE="
KEY_1="VEVTVF9LRVlfMQ=="

IMAGE="coolify-acme-json-certs-map:ci-test"
CONTAINER="coolify-acme-json-certs-map-test"
TIMEOUT=30

PASS=0
FAIL=0
PROXY_DIR=""

# helpers

cleanup() {
    [ -n "$CONTAINER" ] && docker rm -f "$CONTAINER" 2>/dev/null || true
    [ -n "$PROXY_DIR" ] && rm -rf "$PROXY_DIR"
}
trap cleanup EXIT

check() {
    local label="$1" file="$2" expected="$3"
    if [ ! -f "$file" ]; then
        echo "FAIL  $label (file not found)"
        (( FAIL++ )) || true
        return
    fi
    local actual; actual="$(cat "$file")"
    if [ "$actual" = "$expected" ]; then
        echo "PASS  $label"
        (( PASS++ )) || true
    else
        echo "FAIL  $label"
        echo "      expected: $expected"
        echo "      actual:   $actual"
        (( FAIL++ )) || true
    fi
}

# Wait until both files exist
wait_files() {
    local deadline=$(( $(date +%s) + $1 )) f1="$2" f2="$3"
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ -f "$f1" ] && [ -f "$f2" ] && return 0
        sleep 1
    done
    return 1
}

# Wait until a file's content equals the expected string
wait_content() {
    local deadline=$(( $(date +%s) + $1 )) file="$2" expected="$3"
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ -f "$file" ] && [ "$(cat "$file")" = "$expected" ] && return 0
        sleep 1
    done
    return 1
}

# Fill in __CERT__ / __KEY__ placeholders and write to destination
make_acme() {
    local cert="$1" key="$2" dest="$3"
    sed -e "s|__CERT__|$cert|g" -e "s|__KEY__|$key|g" "$SCRIPT_DIR/acme.json" > "$dest"
}

# build

echo "==> build"
docker build -q -t "$IMAGE" "$PROJECT_DIR"

# setup

mkdir -p "$PROJECT_DIR/tmp"
PROXY_DIR="$(mktemp -d -p "$PROJECT_DIR/tmp" proxy.XXXXXX)"

CERT_FILE="$PROXY_DIR/certs/acme/$DOMAIN/cert.pem"
KEY_FILE="$PROXY_DIR/certs/acme/$DOMAIN/key.pem"

make_acme "$CERT_0" "$KEY_0" "$PROXY_DIR/acme.json"

# start container

echo "==> start container"
docker run -d \
    --name "$CONTAINER" \
    --user "$(id -u):$(id -g)" \
    -v "$PROXY_DIR:/data/coolify/proxy" \
    "$IMAGE"

# test 1: startup

echo "==> test 1: startup"
if wait_files $TIMEOUT "$CERT_FILE" "$KEY_FILE"; then
    check "cert.pem = TEST_CERT_0" "$CERT_FILE" "TEST_CERT_0"
    check "key.pem  = TEST_KEY_0"  "$KEY_FILE"  "TEST_KEY_0"
else
    echo "FAIL  timed out waiting for cert files (startup)"
    docker logs "$CONTAINER"
    (( FAIL += 2 )) || true
fi

# test 2: on-change

echo "==> test 2: on-change"
make_acme "$CERT_1" "$KEY_1" "$PROXY_DIR/acme.json"

if wait_content $TIMEOUT "$CERT_FILE" "TEST_CERT_1"; then
    check "cert.pem = TEST_CERT_1" "$CERT_FILE" "TEST_CERT_1"
    check "key.pem  = TEST_KEY_1"  "$KEY_FILE"  "TEST_KEY_1"
else
    echo "FAIL  timed out waiting for cert update (on-change)"
    docker logs "$CONTAINER"
    (( FAIL += 2 )) || true
fi

# summary

echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
