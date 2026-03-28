#!/bin/bash

set -e

# Source logging utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=logging_utils.sh
source "$SCRIPT_DIR/logging_utils.sh"

usage() {
    local exit_code="${1:-1}"
    echo "Usage: ./start_tailscale.sh [--detach] <tailscale_auth_key>"
    exit "$exit_code"
}

DETACH=0
TAILSCALE_AUTH_KEY=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --detach)
            DETACH=1
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        *)
            if [ -z "$TAILSCALE_AUTH_KEY" ]; then
                TAILSCALE_AUTH_KEY="$1"
                shift
            else
                usage 1
            fi
            ;;
    esac
done

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    usage 1
fi

TAILSCALE_RUN_DIR="${TAILSCALE_RUN_DIR:-/tmp/kagglelink-tailscale}"
TAILSCALE_SOCKET="${TAILSCALE_SOCKET:-$TAILSCALE_RUN_DIR/tailscaled.sock}"
TAILSCALE_STATE="${TAILSCALE_STATE:-$TAILSCALE_RUN_DIR/tailscaled.state}"
TAILSCALED_LOG="${TAILSCALED_LOG:-$TAILSCALE_RUN_DIR/tailscaled.log}"
TAILSCALED_PIDFILE="${TAILSCALED_PIDFILE:-$TAILSCALE_RUN_DIR/tailscaled.pid}"
TAILSCALED_PID=""

build_tailscale_hostname() {
    local raw_hostname sanitized truncated

    raw_hostname="${HOSTNAME:-kaggle}"
    sanitized=$(printf '%s' "$raw_hostname" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')
    sanitized="${sanitized#-}"
    sanitized="${sanitized%-}"

    if [ -z "$sanitized" ]; then
        sanitized="kaggle"
    fi

    truncated=$(printf '%.40s' "$sanitized")
    echo "kagglelink-${truncated}"
}

wait_for_tailscaled_socket() {
    local attempt

    for attempt in {1..30}; do
        if [ -S "$TAILSCALE_SOCKET" ]; then
            return 0
        fi

        if [ -n "$TAILSCALED_PID" ] && ! kill -0 "$TAILSCALED_PID" 2>/dev/null; then
            return 1
        fi

        sleep 1
    done

    return 1
}

cleanup() {
    if [ -S "$TAILSCALE_SOCKET" ]; then
        log_info "Disconnecting Tailscale node..."
        tailscale --socket "$TAILSCALE_SOCKET" logout >/dev/null 2>&1 || tailscale --socket "$TAILSCALE_SOCKET" down >/dev/null 2>&1 || true
    fi

    if [ -n "$TAILSCALED_PID" ]; then
        kill "$TAILSCALED_PID" >/dev/null 2>&1 || true
    fi

    rm -rf "$TAILSCALE_RUN_DIR"
    log_success "Cleanup complete."
}

trap cleanup EXIT INT TERM

log_info "Starting Tailscale service..."
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    categorize_error "prerequisite" "TAILSCALE_AUTH_KEY not provided" "Provide an auth key via -a/--auth-key"
    exit 1
fi

mkdir -p "$TAILSCALE_RUN_DIR"
rm -f "$TAILSCALE_SOCKET"

log_step_start "Starting tailscaled in userspace mode"
nohup tailscaled --tun=userspace-networking --state "$TAILSCALE_STATE" --socket "$TAILSCALE_SOCKET" < /dev/null >"$TAILSCALED_LOG" 2>&1 &
TAILSCALED_PID=$!
echo "$TAILSCALED_PID" > "$TAILSCALED_PIDFILE"

if ! wait_for_tailscaled_socket; then
    categorize_error "upstream" "tailscaled did not create its control socket" "Inspect ${TAILSCALED_LOG} and retry"
    exit 1
fi
log_step_complete "Starting tailscaled in userspace mode"

TAILSCALE_HOSTNAME=$(build_tailscale_hostname)

log_step_start "Joining tailnet with the provided auth key"
if ! tailscale --socket "$TAILSCALE_SOCKET" up --auth-key "$TAILSCALE_AUTH_KEY" --hostname "$TAILSCALE_HOSTNAME" --ssh --accept-dns=false --accept-routes=false --reset; then
    categorize_error "upstream" "Failed to join the tailnet with the provided auth key" "Verify the auth key is valid and check your tailnet SSH policy"
    exit 1
fi
log_step_complete "Joining tailnet with the provided auth key"

TAILSCALE_IPV4=""
for attempt in {1..20}; do
    TAILSCALE_IPV4=$(tailscale --socket "$TAILSCALE_SOCKET" ip -4 2>/dev/null | head -n 1 || true)
    if [ -n "$TAILSCALE_IPV4" ]; then
        break
    fi
    sleep 1
done

TAILSCALE_DNS_NAME=$(tailscale --socket "$TAILSCALE_SOCKET" status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || true)

if [ -z "$TAILSCALE_IPV4" ] && [ -z "$TAILSCALE_DNS_NAME" ]; then
    categorize_error "upstream" "Tailscale connected but no node address was reported" "Check tailnet connectivity and inspect tailscale status"
    exit 1
fi

show_tailscale_success_banner "$TAILSCALE_HOSTNAME" "$TAILSCALE_DNS_NAME" "$TAILSCALE_IPV4"

if [ "$DETACH" = "1" ]; then
    log_success "Detached mode enabled. Tailscale will keep running in the background."
    log_info "Log file: $TAILSCALED_LOG"
    log_info "PID file: $TAILSCALED_PIDFILE"
    trap - EXIT INT TERM
    exit 0
fi

log_info "Tailscale node is active. Keeping connection alive..."
log_info "Press Ctrl+C to disconnect the node and stop the daemon."
wait "$TAILSCALED_PID"
