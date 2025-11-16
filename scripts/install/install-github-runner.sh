#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions Self-Hosted Runner Installation Script
# Installs and configures GitHub Actions runner as a systemd service
#
# Usage:
#   ./install-github-runner.sh <github-repo-url> <runner-token>
#
# Example:
#   ./install-github-runner.sh https://github.com/username/repo ghp_abc123...
#
# Note: Get the runner token from:
#   GitHub → Repository → Settings → Actions → Runners → New self-hosted runner

REPO_URL="${1:-}"
RUNNER_TOKEN="${2:-}"
RUNNER_VERSION="2.321.0"
RUNNER_DIR="${HOME}/actions-runner"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_usage() {
    cat << EOF
GitHub Actions Self-Hosted Runner Installer

Usage:
    $0 <github-repo-url> <runner-token>

Arguments:
    github-repo-url    Full URL to your GitHub repository
                       Example: https://github.com/username/repo

    runner-token       Registration token from GitHub
                       Get from: Settings → Actions → Runners → New runner

Example:
    $0 https://github.com/fuentastic/curriculum-vitae ghp_abc123def456...

Prerequisites:
    - Linux x64 system
    - Sudo access for systemd service installation
    - Internet connection to download runner
EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if running on Linux
    if [[ "$(uname -s)" != "Linux" ]]; then
        log_error "This script only works on Linux systems"
        exit 1
    fi

    # Check architecture
    if [[ "$(uname -m)" != "x86_64" ]]; then
        log_error "This script only supports x86_64 architecture"
        exit 1
    fi

    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install it first."
        exit 1
    fi

    # Check if tar is installed
    if ! command -v tar &> /dev/null; then
        log_error "tar is not installed. Please install it first."
        exit 1
    fi

    log_info "Prerequisites check passed ✓"
}

validate_inputs() {
    if [[ -z "$REPO_URL" ]] || [[ -z "$RUNNER_TOKEN" ]]; then
        log_error "Missing required arguments"
        echo
        print_usage
        exit 1
    fi

    # Validate GitHub URL format
    if [[ ! "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+$ ]]; then
        log_error "Invalid GitHub repository URL format"
        log_error "Expected: https://github.com/username/repository"
        log_error "Got: $REPO_URL"
        exit 1
    fi

    log_info "Input validation passed ✓"
}

check_existing_runner() {
    if [[ -d "$RUNNER_DIR" ]]; then
        log_warn "Runner directory already exists: $RUNNER_DIR"

        # Check if service is running
        if sudo systemctl is-active --quiet actions.runner.* 2>/dev/null; then
            log_error "GitHub Actions runner service is already running"
            log_error "To reinstall, first stop and remove the existing service:"
            echo
            echo "    sudo ~/actions-runner/svc.sh stop"
            echo "    sudo ~/actions-runner/svc.sh uninstall"
            echo "    rm -rf ~/actions-runner"
            echo
            exit 1
        fi

        # Offer to remove existing directory
        read -p "Remove existing directory and continue? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing runner directory..."
            rm -rf "$RUNNER_DIR"
        else
            log_error "Installation cancelled"
            exit 1
        fi
    fi
}

download_runner() {
    log_info "Creating runner directory: $RUNNER_DIR"
    mkdir -p "$RUNNER_DIR"
    cd "$RUNNER_DIR"

    log_info "Downloading GitHub Actions runner v${RUNNER_VERSION}..."
    local download_url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"

    curl -o actions-runner-linux-x64.tar.gz -L "$download_url"

    if [[ ! -f "actions-runner-linux-x64.tar.gz" ]]; then
        log_error "Failed to download runner package"
        exit 1
    fi

    log_info "Extracting runner package..."
    tar xzf ./actions-runner-linux-x64.tar.gz

    # Verify extraction
    if [[ ! -f "./config.sh" ]]; then
        log_error "Failed to extract runner package"
        exit 1
    fi

    # Clean up tarball
    rm actions-runner-linux-x64.tar.gz

    log_info "Runner downloaded and extracted ✓"
}

configure_runner() {
    log_info "Configuring GitHub Actions runner..."

    cd "$RUNNER_DIR"

    # Extract repo name from URL for runner name
    local repo_name
    repo_name=$(basename "$REPO_URL")
    local runner_name="${HOSTNAME:-$(hostname)}-${repo_name}"

    log_info "Runner name: $runner_name"
    log_info "Repository: $REPO_URL"

    # Run configuration non-interactively
    ./config.sh \
        --url "$REPO_URL" \
        --token "$RUNNER_TOKEN" \
        --name "$runner_name" \
        --labels "self-hosted,Linux,X64" \
        --work "_work" \
        --unattended \
        --replace

    if [[ $? -ne 0 ]]; then
        log_error "Failed to configure runner"
        log_error "Common issues:"
        log_error "  - Invalid or expired runner token"
        log_error "  - Network connectivity issues"
        log_error "  - Repository URL is incorrect"
        exit 1
    fi

    log_info "Runner configured ✓"
}

install_service() {
    log_info "Installing runner as systemd service..."

    cd "$RUNNER_DIR"

    # Install service (requires sudo)
    sudo ./svc.sh install

    if [[ $? -ne 0 ]]; then
        log_error "Failed to install systemd service"
        exit 1
    fi

    log_info "Starting runner service..."
    sudo ./svc.sh start

    if [[ $? -ne 0 ]]; then
        log_error "Failed to start runner service"
        exit 1
    fi

    # Wait a moment for service to start
    sleep 2

    # Check service status
    if sudo ./svc.sh status | grep -q "active (running)"; then
        log_info "Runner service started successfully ✓"
    else
        log_error "Runner service failed to start"
        log_error "Check logs with: journalctl -u actions.runner.* -f"
        exit 1
    fi
}

print_success() {
    local repo_name
    repo_name=$(basename "$REPO_URL")

    cat << EOF

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${GREEN}✓ GitHub Actions Runner Installed Successfully!${NC}
${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

Repository:  ${REPO_URL}
Runner Dir:  ${RUNNER_DIR}
Service:     actions.runner.${USER}.${repo_name}

Useful Commands:
    Check status:    sudo systemctl status actions.runner.*
    View logs:       journalctl -u actions.runner.* -f
    Restart:         sudo systemctl restart actions.runner.*
    Stop:            sudo ${RUNNER_DIR}/svc.sh stop
    Uninstall:       sudo ${RUNNER_DIR}/svc.sh uninstall

Next Steps:
    1. Verify runner appears in GitHub:
       ${REPO_URL}/settings/actions/runners

    2. Push code to trigger workflow

    3. Monitor runner logs:
       journalctl -u actions.runner.* -f

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
EOF
}

main() {
    log_info "GitHub Actions Runner Installation"
    echo

    # Validate inputs first
    validate_inputs

    # Check prerequisites
    check_prerequisites

    # Check for existing runner
    check_existing_runner

    # Download runner package
    download_runner

    # Configure runner
    configure_runner

    # Install as systemd service
    install_service

    # Print success message
    print_success
}

# Run main function
main
