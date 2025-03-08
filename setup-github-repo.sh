#!/bin/bash

# Function to log messages
log() {
    echo "$(date +"%Y-%m-%d_%H:%M:%S") - $1"
}
mkdir -p setup-logs
LOG_FILE="setup-logs/setup-$(date +"%Y-%m-%d_%H:%M:%S").log"
#Start logging
exec > >(tee -a "$LOG_FILE") 2>&1



#### ENVIRONMENTS ####
# Find all .env* files
ENV_FILES=($(ls -1 .env* 2>/dev/null))

# Remove non-existing filenames (if no .env* files exist)
ENV_FILES=("${ENV_FILES[@]}")
ENV_FILES=($(ls -1 .env* 2>/dev/null))

# Inform the user about required variables
log "The following variables are required:"
log "- TOKEN (GitHub token)"
log "- GITHUB_USER (GitHub username)"
log "- REPO_NAME (Repository name)"
log

# List available .env* files
log "Choose an option:"
log "0 - Enter values manually"
for i in "${!ENV_FILES[@]}"; do
    log "$((i+1)) - ${ENV_FILES[$i]}"
done

log
read -p "Enter the number of your choice: " CHOICE

env_file=""
if [[ "$CHOICE" -ne 0 ]]; then
    env_file="${ENV_FILES[$((CHOICE-1))]}"
    if [[ ! -f "$env_file" ]]; then
        log "Invalid selection. Proceeding with manual input."
    else
        log "Using environment file: $env_file"
        set -o allexport
        source "$env_file"
        set +o allexport
    fi
fi

# Prompt for missing variables
if [[ -z "$TOKEN" ]]; then
    read -p "Enter your GitHub token: " TOKEN
fi

if [[ -z "$GITHUB_USER" ]]; then
    read -p "Enter your GitHub username: " GITHUB_USER
fi

if [[ -z "$REPO_NAME" ]]; then
    read -p "Enter the repository name: " REPO_NAME
fi

# Confirm collected values
log "Using the following values:"
log "TOKEN: [HIDDEN]"
log "GITHUB_USER: $GITHUB_USER"
log "REPO_NAME: $REPO_NAME"
#### ENVIRONMENTS ####


# Define variables
REPO_URL="https://$TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git"
REPO_NAME=$(basename "$REPO_URL" .git)
REPO_DIR="$HOME/github/$REPO_NAME"
SERVICE_NAME="${REPO_NAME}.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

# Display variables
log "REPO_URL = $REPO_URL"
log "REPO_NAME = $REPO_NAME"
log "REPO_DIR = $REPO_DIR"
log "SERVICE_NAME = $SERVICE_NAME"
log "SERVICE_FILE = $SERVICE_FILE"



# Prompt for system update and upgrade
read -p "Do you want to update and upgrade the system? (y/n): " UPDATE_SYSTEM
if [[ "$UPDATE_SYSTEM" =~ ^[Yy]$ ]]; then
    log "Updating and upgrading the system..."
    if sudo apt update && sudo apt upgrade -y; then
        log "System updated and upgraded successfully."
    else
        log "Error: Failed to update and upgrade the system."
        exit 1
    fi
else
    log "Skipping system update and upgrade."
fi


# Check if git is installed (if not, install it)
if ! command -v git &>/dev/null; then
    log "Git is not installed. Installing Git..."
    if sudo apt install git -y; then
        log "Git installed successfully."
    else
        log "Error: Failed to install Git."
        exit 1
    fi
else
    log "Git is already installed."
fi



# Display the current directory
log "Current directory: $(pwd)"

# Ensure the target directory exists
mkdir -p "$HOME/github"

# Clone or update the repository
if [ ! -d "$REPO_DIR" ]; then
    log "Cloning repository from $REPO_URL into $REPO_DIR..."
    if git clone "$REPO_URL" "$REPO_DIR"; then
        log "Repository cloned successfully."
    else
        log "Error: Failed to clone the repository."
        exit 1
    fi
else
    log "Repository already exists at $REPO_DIR. Pulling latest changes..."
    cd "$REPO_DIR" || exit 1
    if git pull; then
        log "Repository updated successfully."
    else
        log "Error: Failed to update the repository."
        exit 1
    fi
fi

# Navigate to the repository directory
log "Navigating to repository directory: $REPO_DIR"
cd "$REPO_DIR" || {
    log "Error: Failed to navigate to repository directory."
    exit 1
}

# Grant execute permissions to the start.sh script
if [ -f "start.sh" ]; then
    log "Ensuring start.sh has execute permissions."
    chmod +x start.sh
else
    log "Error: start.sh script not found in the repository."
    exit 1
fi


# Creating repo autorun service if not exists
if systemctl list-units --type=service --all | grep -q "$SERVICE_NAME"; then
    log "Service $SERVICE_NAME is already recognized by systemd."
else
    log "Creating systemd service file: $SERVICE_FILE"
    sudo bash -c "cat > $SERVICE_FILE" <<EOL
[Unit]
Description=Service to run $REPO_DIR's start.sh script
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/start.sh
Restart=always
RestartSec=10
MemoryAccounting=true
MemoryMax=2G

[Install]
WantedBy=multi-user.target
EOL
    log "Systemd service file created."
    log "Reloading systemd daemon..."
    sudo systemctl daemon-reload
fi



# Check current service status
SERVICE_STATUS=$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || echo "Service status is NOT enabled")
if [[ "$SERVICE_STATUS" == "enabled" ]]; then
    log "Service $SERVICE_NAME is already enabled."
else
    log "Enabling service $SERVICE_NAME..."
    sudo systemctl enable "$SERVICE_NAME"
fi

# Check if the service is running
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "Service $SERVICE_NAME is already running."
else
    log "Starting service $SERVICE_NAME..."
    sudo systemctl start "$SERVICE_NAME"
fi

# Check service status
log "Checking service status..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "Service $SERVICE_NAME is running successfully."
else
    log "Error: Service $SERVICE_NAME failed to start."
    exit 1
fi



log "Setup completed successfully."
