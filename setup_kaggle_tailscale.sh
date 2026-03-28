#!/bin/bash

set -e

# Source logging utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=logging_utils.sh
source "$SCRIPT_DIR/logging_utils.sh"

if [ "$#" -ne 1 ]; then
    echo "Usage: ./setup_kaggle_tailscale.sh <authorized_keys_url>"
    exit 1
fi

AUTH_KEYS_URL=$1

setup_ssh_directory() {
    log_info "Setting up SSH directory in user's home..."
    local ssh_dir_path="$HOME/.ssh"
    mkdir -p "$ssh_dir_path"

    if wget -qO "$ssh_dir_path/authorized_keys" "$AUTH_KEYS_URL"; then
        chmod 700 "$ssh_dir_path"
        chmod 600 "$ssh_dir_path/authorized_keys"
        log_success "SSH directory and authorized_keys set up in $ssh_dir_path"
    else
        categorize_error "network" "Failed to download authorized keys from $AUTH_KEYS_URL" "Check URL accessibility and internet connectivity"
        exit 1
    fi
}

copy_vscode_dir() {
    local vscode_dir_in_repo="/tmp/kagglelink/.vscode"
    if [ -d "$vscode_dir_in_repo" ]; then
        [ -d "/kaggle/.vscode" ] && rm -rf "/kaggle/.vscode"
        mkdir -p "/kaggle/.vscode"
        cp -r "$vscode_dir_in_repo/"* "/kaggle/.vscode/"
        log_info ".vscode folder copied to /kaggle directory."

        mkdir -p "/kaggle/tmp"
        [ -d "/kaggle/working/.vscode" ] && rm -rf "/kaggle/working/.vscode"
        mkdir -p "/kaggle/working/.vscode"
        cp -r "$vscode_dir_in_repo/"* "/kaggle/working/.vscode/"
        log_info ".vscode folder copied to /kaggle/working directory."

        log_info "Contents of /kaggle/.vscode:"
        ls -l "/kaggle/.vscode"
        log_info "Contents of /kaggle/working/.vscode:"
        ls -l "/kaggle/working/.vscode"
    else
        log_error ".vscode directory not found in repository at $vscode_dir_in_repo."
    fi
}

configure_sshd() {
    mkdir -p /var/run/sshd
    log_info "Configuring sshd..."
    cat <<EOF >>/etc/ssh/sshd_config
Port 22
Protocol 2
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile %h/.ssh/authorized_keys
TCPKeepAlive yes
X11Forwarding yes
X11DisplayOffset 10
IgnoreRhosts yes
HostbasedAuthentication no
PrintLastLog yes
ChallengeResponseAuthentication no
UsePAM yes
AcceptEnv LANG LC_*
AllowTcpForwarding yes
GatewayPorts yes
PermitTunnel yes
ClientAliveInterval 60
ClientAliveCountMax 2
EOF
    echo "" >>/etc/ssh/sshd_config
    log_success "sshd_config updated. Note: Appended settings. Ensure no conflicting duplicates exist if run multiple times."

    log_info "Configuring debconf for non-interactive mode..."
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
    log_success "debconf configured to use Noninteractive frontend."

    log_info "Disabling pam_systemd..."
    sed -i 's/^session.*pam_systemd.so/#&/' /etc/pam.d/common-session

    log_info "Disabling man-db postinst script..."
    dpkg-divert --quiet --local --rename --add /var/lib/dpkg/info/man-db.postinst
    ln -sf /bin/true /var/lib/dpkg/info/man-db.postinst

    log_success "Container compatibility fixes applied."
}

setup_environment_variables() {
    echo "Appending current environment variables to /root/.bashrc..."
    {
        echo ""
        echo "# Added by setup_kaggle_tailscale.sh: Kaggle instance environment variables"
        printenv | while IFS='=' read -r key value; do
            if [[ "$key" == "PWD" || "$key" == "OLDPWD" || "$key" == "TERM" ||
                "$key" == "DEBIAN_FRONTEND" || "$key" == "SHELL" ||
                "$key" == "_" || "$key" == "SHLVL" || "$key" == "HOSTNAME" ||
                "$key" == "JPY_PARENT_PID" || "$key" =~ ^COLAB_ || "$key" =~ ^BASH_ ]]; then
                continue
            fi

            escaped_value_final=$(printf "%s" "$value" | sed "s/'/'\\\''/g")
            echo "export ${key}='${escaped_value_final}'"
        done
        echo "export MPLBACKEND=Agg"
        echo "# End of Kaggle instance environment variables"

        echo "# Directory navigation aliases"
        {
            echo "alias ..='cd ..'"
            echo "alias ...='cd ../..'"
            echo "alias .3='cd ../../..'"
            echo "alias .4='cd ../../../..'"
            echo "alias .5='cd ../../../../..'"
        } >>/root/.bashrc

        echo "# Dynamic VS Code server path resolution"
        cat <<'EOT'
# Dynamic VS Code server path resolution
if [ -d "$HOME/.vscode-server" ]; then
  VSCODE_SERVER_DIR=$(find "$HOME/.vscode-server/cli/servers" -type d -name "Stable-*" | sort | tail -n 1)
  if [ -n "$VSCODE_SERVER_DIR" ]; then
    export PATH="$VSCODE_SERVER_DIR/server/bin/remote-cli:$PATH"
  fi
fi
EOT
        echo ""
    } >>/root/.bashrc

    echo "Sourcing /root/.bashrc for current script session (best effort)..."
    # shellcheck disable=SC1091
    source /root/.bashrc || echo "Warning: Sourcing /root/.bashrc encountered an issue. SSH sessions should still inherit env vars."
}

install_packages() {
    log_step_start "Installing packages"

    apt-get update
    apt-get install -y ca-certificates curl gnupg

    log_info "Installing gum..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list >/dev/null

    apt-get update
    apt-get install -y openssh-server nvtop screen lshw gum jq
    log_step_complete "Installing packages"

    log_info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
}

install_tailscale() {
    local install_script

    log_step_start "Installing Tailscale"

    if ! install_script=$(mktemp); then
        categorize_error "upstream" "Failed to create a temporary file for Tailscale installation" "Check filesystem permissions and retry"
        exit 1
    fi

    if ! curl -fsSL https://tailscale.com/install.sh -o "$install_script"; then
        rm -f "$install_script"
        categorize_error "network" "Failed to download the Tailscale install script" "Verify access to tailscale.com and retry"
        exit 1
    fi

    if ! sh "$install_script"; then
        rm -f "$install_script"
        categorize_error "upstream" "Tailscale install script failed" "Review install output and retry"
        exit 1
    fi

    rm -f "$install_script"

    if ! tailscale version &>/dev/null; then
        categorize_error "upstream" "Post-install validation failed for Tailscale" "Verify the tailscale CLI is on PATH and rerun setup"
        exit 1
    fi

    log_step_complete "Installing Tailscale"
    log_success "Tailscale version: $(tailscale version | head -n 1)"
}

setup_install_extensions_command() {
    log_info "Setting up 'install_extensions' command..."
    local install_script_source="$SCRIPT_DIR/install_extensions.sh"
    local install_script_target="/usr/local/bin/install_extensions"

    if [ -f "$install_script_source" ]; then
        mkdir -p /usr/local/bin
        cp "$install_script_source" "$install_script_target"
        chmod +x "$install_script_target"
        log_success "'install_extensions' command is now available from $install_script_target."
    else
        log_error "$install_script_source not found. 'install_extensions' command not set up."
    fi
}

start_ssh_service() {
    service ssh start
    log_success "SSH service is running."
}

copy_screenrc() {
    local src="/tmp/kagglelink/.screenrc"
    local dest="$HOME/.screenrc"
    if [ -f "$src" ]; then
        cp "$src" "$dest"
        log_info ".screenrc installed to $dest"
    else
        log_error "$src not found; skipping .screenrc install."
    fi
}

(
    setup_environment_variables
    install_packages
    install_tailscale
    setup_ssh_directory
    configure_sshd
    copy_vscode_dir &
    copy_screenrc &
    setup_install_extensions_command
    wait
    start_ssh_service
)

log_success "Setup script completed. SSH service is running. Use start_tailscale.sh to join the tailnet."
