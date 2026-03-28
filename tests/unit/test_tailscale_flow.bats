#!/usr/bin/env bats
# Focused tests for the Tailscale-first KaggleLink flow

load '../test_helper/common'

setup() {
    create_test_dir
}

teardown() {
    cleanup_test_dir
}

@test "P0: setup.sh advertises Tailscale auth key support" {
    run grep -E -- "--auth-key|KAGGLELINK_AUTH_KEY" "${PROJECT_ROOT}/setup.sh"
    [ "$status" -eq 0 ]
}

@test "P0: setup.sh starts Tailscale in detached mode by default" {
    run grep -E -- "start_tailscale\.sh --detach|KAGGLELINK_TAILSCALE_FOREGROUND" "${PROJECT_ROOT}/setup.sh"
    [ "$status" -eq 0 ]
}

@test "P0: setup_kaggle_tailscale.sh installs Tailscale from the official install script" {
    run grep -E "tailscale\.com/install\.sh" "${PROJECT_ROOT}/setup_kaggle_tailscale.sh"
    [ "$status" -eq 0 ]

    run grep -E "tailscale version" "${PROJECT_ROOT}/setup_kaggle_tailscale.sh"
    [ "$status" -eq 0 ]
}

@test "P0: start_tailscale.sh launches tailscaled in userspace mode" {
    run grep -E "tailscaled .*--tun=userspace-networking" "${PROJECT_ROOT}/start_tailscale.sh"
    [ "$status" -eq 0 ]
}

@test "P0: start_tailscale.sh opts the node into Tailscale SSH" {
    run grep -E "tailscale .* up .*--ssh" "${PROJECT_ROOT}/start_tailscale.sh"
    [ "$status" -eq 0 ]
}

@test "P1: start_tailscale.sh cleans up the Tailscale session on exit" {
    run grep -E "trap cleanup EXIT INT TERM" "${PROJECT_ROOT}/start_tailscale.sh"
    [ "$status" -eq 0 ]

    run grep -E "tailscale .* (logout|down)" "${PROJECT_ROOT}/start_tailscale.sh"
    [ "$status" -eq 0 ]
}

@test "P1: start_tailscale.sh supports detached mode" {
    run grep -E -- "Usage: ./start_tailscale.sh \\[--detach\\]|Detached mode enabled" "${PROJECT_ROOT}/start_tailscale.sh"
    [ "$status" -eq 0 ]
}

@test "P1: stop_tailscale.sh supports preserving or removing state" {
    run grep -E -- "tailscale --socket .* down|tailscale --socket .* logout|--logout" "${PROJECT_ROOT}/stop_tailscale.sh"
    [ "$status" -eq 0 ]
}

@test "P1: show_tailscale_success_banner prints SSH instructions" {
    source "${PROJECT_ROOT}/logging_utils.sh"

    run show_tailscale_success_banner "kagglelink-demo" "kagglelink-demo.example.ts.net" "100.64.0.10"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Tailscale"* ]]
    [[ "$output" == *"ssh root@kagglelink-demo.example.ts.net"* ]]
    [[ "$output" == *"100.64.0.10"* ]]
}
