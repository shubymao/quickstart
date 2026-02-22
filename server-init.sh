#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit
fi

USERNAME="admin"

# 1. User and Home Directory Management
if ! id "$USERNAME" &>/dev/null; then
  echo "--- Creating User: $USERNAME ---"
  # Prompt for password securely
  read -s -p "Enter password for $USERNAME: " USER_PASS
  echo
  read -s -p "Confirm password: " USER_PASS_CONFIRM
  echo

  if [ "$USER_PASS" != "$USER_PASS_CONFIRM" ]; then
    echo "Passwords do not match. Exiting."
    exit 1
  fi

  # Create user with the provided password
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:$USER_PASS" | chpasswd
  echo "User $USERNAME created successfully."
else
  echo "User $USERNAME already exists."
fi

# Ensure home folder exists and ownership is correct
# (Checks even if the user already existed previously)
HOME_DIR="/home/$USERNAME"
if [ ! -d "$HOME_DIR" ]; then
  echo "Home directory missing. Creating $HOME_DIR..."
  mkdir -p "$HOME_DIR"
fi

echo "Setting ownership of $HOME_DIR to $USERNAME..."
chown -R "$USERNAME":"$USERNAME" "$HOME_DIR"

# 2. Install sudo if not exist
if ! command -v sudo &>/dev/null; then
  apt update && apt install -y sudo
fi

# 3. Add admin to sudo
if ! groups "$USERNAME" | grep -q "\bsudo\b"; then
  usermod -aG sudo "$USERNAME"
  echo "Added $USERNAME to sudo group."
fi

# 4. SSH Key Management
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Check if authorized_keys is empty or missing
if [ ! -f "$AUTH_KEYS" ] || [ ! -s "$AUTH_KEYS" ]; then
  echo "--- SSH Key Setup ---"
  read -p "Paste your public SSH key (starting with ssh-rsa/ssh-ed25519): " NEW_KEY

  # Only add if the key isn't already in the file
  if ! grep -qF "$NEW_KEY" "$AUTH_KEYS" 2>/dev/null; then
    echo "$NEW_KEY" >>"$AUTH_KEYS"
    echo "SSH key added."
  fi
fi
chown -R "$USERNAME":"$USERNAME" "$SSH_DIR"
chmod 600 "$AUTH_KEYS"

# 5. Install and Start SSH
if ! command -v sshd &>/dev/null; then
  apt update && apt install -y openssh-server
fi
systemctl enable --now ssh

# 6. Bulletproof SSH Hardening
echo "--- Hardening SSH Configuration ---"
CONFIG_FILE="/etc/ssh/sshd_config"

set_ssh_config() {
  local key=$1
  local value=$2
  if grep -q "^#\?$key" "$CONFIG_FILE"; then
    sed -i "s|^#\?$key.*|$key $value|" "$CONFIG_FILE"
  else
    echo "$key $value" >>"$CONFIG_FILE"
  fi
}

set_ssh_config "PermitRootLogin" "no"
set_ssh_config "PasswordAuthentication" "no"
set_ssh_config "PubkeyAuthentication" "yes"

# Final Syntax Check
if /usr/sbin/sshd -t; then
  systemctl restart ssh
  echo "Success! SSH is secured. Root and Password logins are DISABLED."
else
  echo "Warning: SSH config has errors. Check $CONFIG_FILE manually."
  exit 1
fi
