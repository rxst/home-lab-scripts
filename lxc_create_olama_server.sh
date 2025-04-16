#!/usr/bin/env bash

# This script automates the creation and registration of a Github self-hosted runner within a Proxmox LXC (Linux Container).
# The runner is based on Ubuntu 23.04. Before running the script, ensure you have your GITHUB_TOKEN 
# and the OWNERREPO (github owner/repository) available.

set -e

# Variables
TEMPL_URL="http://download.proxmox.com/images/system/ubuntu-23.04-standard_23.04-1_amd64.tar.zst"
PCTSIZE="20G"
PCT_ARCH="amd64"
PCT_CORES="4"
PCT_MEMORY="4096"
PCT_SWAP="4096"
PCT_STORAGE="local-lvm"
DEFAULT_IP_ADDR="192.168.0.123/24"
DEFAULT_GATEWAY="192.168.0.1"
MODEL_NAME="llama3.2:1b"

# log function prints text in yellow
log() {
  local text="$1"
  echo -e "\033[33m$text\033[0m"
}

# Prompt for network details
read -r -e -p "Container Address IP (CIDR format) [$DEFAULT_IP_ADDR]: " input_ip_addr
IP_ADDR=${input_ip_addr:-$DEFAULT_IP_ADDR}
read -r -e -p "Container Gateway IP [$DEFAULT_GATEWAY]: " input_gateway
GATEWAY=${input_gateway:-$DEFAULT_GATEWAY}

# Get filename from the URLs
TEMPL_FILE=$(basename $TEMPL_URL)

# Get the next available ID from Proxmox
PCTID=$(pvesh get /cluster/nextid)

# Download Ubuntu template
log "-- Downloading $TEMPL_FILE template..."
curl -q -C - -o "$TEMPL_FILE" $TEMPL_URL

# Create LXC container
log "-- Creating LXC container with ID:$PCTID"
pct create "$PCTID" "$TEMPL_FILE" \
   -arch $PCT_ARCH \
   -ostype ubuntu \
   -hostname github-runner-proxmox-$(openssl rand -hex 3) \
   -cores $PCT_CORES \
   -memory $PCT_MEMORY \
   -swap $PCT_SWAP \
   -storage $PCT_STORAGE \
   -features nesting=1,keyctl=1 \
   -net0 name=eth0,bridge=vmbr0,gw="$GATEWAY",ip="$IP_ADDR",type=veth

# Resize the container
log "-- Resizing container to $PCTSIZE"
pct resize "$PCTID" rootfs $PCTSIZE

# Start the container & run updates inside it
log "-- Starting container"
pct start "$PCTID"
sleep 10
log "-- Running updates"
pct exec "$PCTID" -- bash -c "apt update -y && apt install -y git curl zip && passwd -d root"

# Install Ollama inside the container
log "-- Installing Ollama"
pct exec "$PCTID" -- bash -c "curl -fsSL https://ollama.com/install.sh | sh"
log "-- Start Ollama service"
pct exec "$PCTID" -- bash -c "systemctl enable ollama && systemctl start ollama"
log "-- Run model"
pct exec "$PCTID" -- bash -c "ollama run $MODEL_NAME"
# Delete the downloaded Ubuntu template
rm "$TEMPL_FILE"
