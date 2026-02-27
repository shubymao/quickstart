#!/bin/bash
set -euo pipefail

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit
fi

USERNAME="admin"
HARDEN_SSH="false"

if [[ "${1:-}" == "--harden-ssh" ]]; then
  HARDEN_SSH="true"
fi

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

is_valid_pubkey() {
  [[ "$1" =~ ^ssh-(ed25519|rsa|ecdsa-[^[:space:]]+)[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]]
}

# Check if authorized_keys is empty or missing
if [ ! -f "$AUTH_KEYS" ] || [ ! -s "$AUTH_KEYS" ]; then
  echo "--- SSH Key Setup ---"
  while true; do
    read -r -p "Paste your public SSH key (ssh-ed25519/ssh-rsa/ssh-ecdsa): " NEW_KEY
    if is_valid_pubkey "$NEW_KEY"; then
      break
    fi
    echo "Invalid SSH public key format. Try again."
  done

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

# 6. Optional SSH hardening (run with --harden-ssh after key login is verified)
if [[ "$HARDEN_SSH" == "true" ]]; then
  if ! grep -Eq '^ssh-(ed25519|rsa|ecdsa-)' "$AUTH_KEYS"; then
    echo "No valid SSH public key found in $AUTH_KEYS. Refusing to disable password login."
    exit 1
  fi

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

  if /usr/sbin/sshd -t; then
    systemctl restart ssh
    echo "Success! SSH is secured. Root and password logins are disabled."
  else
    echo "Warning: SSH config has errors. Check $CONFIG_FILE manually."
    exit 1
  fi
else
  echo "SSH key bootstrap completed. Password auth is still enabled."
  echo "After confirming key login works, rerun with --harden-ssh to disable password auth."
fi
