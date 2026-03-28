#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=logging_utils.sh
source "$SCRIPT_DIR/logging_utils.sh"

TAILSCALE_RUN_DIR="${TAILSCALE_RUN_DIR:-/tmp/kagglelink-tailscale}"
TAILSCALE_SOCKET="${TAILSCALE_SOCKET:-$TAILSCALE_RUN_DIR/tailscaled.sock}"
TAILSCALED_PIDFILE="${TAILSCALED_PIDFILE:-$TAILSCALE_RUN_DIR/tailscaled.pid}"
TAILSCALE_LOGOUT=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --logout)
            TAILSCALE_LOGOUT=1
            shift
            ;;
        -h|--help)
            echo "Usage: ./stop_tailscale.sh [--logout]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: ./stop_tailscale.sh [--logout]"
            exit 1
            ;;
    esac
done

if [ -S "$TAILSCALE_SOCKET" ]; then
    if [ "$TAILSCALE_LOGOUT" = "1" ]; then
        log_info "Logging out the Tailscale node..."
        tailscale --socket "$TAILSCALE_SOCKET" logout || true
    else
        log_info "Stopping the Tailscale connection while keeping node state..."
        tailscale --socket "$TAILSCALE_SOCKET" down || true
    fi
fi

if [ -f "$TAILSCALED_PIDFILE" ]; then
    TAILSCALED_PID=$(cat "$TAILSCALED_PIDFILE" 2>/dev/null || true)
    if [ -n "$TAILSCALED_PID" ]; then
        kill "$TAILSCALED_PID" 2>/dev/null || true
    fi
    rm -f "$TAILSCALED_PIDFILE"
fi

if [ "$TAILSCALE_LOGOUT" = "1" ]; then
    rm -rf "$TAILSCALE_RUN_DIR"
    log_success "Tailscale state removed."
else
    log_success "Tailscale daemon stopped. State kept in $TAILSCALE_RUN_DIR."
fi
