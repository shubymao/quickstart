#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

USERNAME="admin"
GITHUB_USER="shubymao"
HOME_DIR="/home/$USERNAME"
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
CRON_JOB_FILE="/etc/cron.d/github-ssh-keys-sync"

# 1. User and Home Directory Management
if ! id "$USERNAME" &>/dev/null; then
  echo "--- Creating User: $USERNAME ---"
  read -s -p "Enter password for $USERNAME: " USER_PASS
  echo
  read -s -p "Confirm password: " USER_PASS_CONFIRM
  echo

  if [ "$USER_PASS" != "$USER_PASS_CONFIRM" ]; then
    echo "Passwords do not match. Exiting."
    exit 1
  fi

  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:$USER_PASS" | chpasswd
  echo "User $USERNAME created successfully."
else
  echo "User $USERNAME already exists."
fi

# Ensure home folder exists
if [ ! -d "$HOME_DIR" ]; then
  echo "Home directory missing. Creating $HOME_DIR..."
  mkdir -p "$HOME_DIR"
fi

echo "Setting ownership of $HOME_DIR to $USERNAME..."
chown -R "$USERNAME":"$USERNAME" "$HOME_DIR"

# 2. Install sudo if not exist
if ! command -v sudo &>/dev/null; then
  echo "--- Installing sudo ---"
  apt update && apt install -y sudo
fi

# 3. Add admin to sudo group
if ! groups "$USERNAME" | grep -q "\bsudo\b"; then
  usermod -aG sudo "$USERNAME"
  echo "Added $USERNAME to sudo group."
fi

# 4. Setup .ssh directory
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
chown -R "$USERNAME":"$USERNAME" "$SSH_DIR"

# 5. Install and Start SSH
if ! command -v sshd &>/dev/null; then
  echo "--- Installing OpenSSH Server ---"
  apt update && apt install -y openssh-server
fi

systemctl enable ssh
systemctl start ssh

# 6. Hardening SSH Configuration
echo "--- Hardening SSH Configuration ---"
CONFIG_FILE="/etc/ssh/sshd_config"

set_ssh_config() {
  local key=$1
  local value=$2
  if grep -qE "^#?\s*${key}" "$CONFIG_FILE"; then
    sed -i -E "s|^#?\s*${key}.*|${key} ${value}|" "$CONFIG_FILE"
  else
    echo "${key} ${value}" >>"$CONFIG_FILE"
  fi
}

set_ssh_config "PermitRootLogin" "no"
set_ssh_config "PasswordAuthentication" "no"
set_ssh_config "PubkeyAuthentication" "yes"

if /usr/sbin/sshd -t 2>/dev/null; then
  systemctl restart ssh
  echo "SSH hardened: Root login and password auth disabled, pubkey auth enabled."
else
  echo "Warning: SSH config test failed. Please check $CONFIG_FILE manually."
fi

# 7. Create cron job script for GitHub SSH keys sync
CRON_SCRIPT="/usr/local/bin/sync-github-ssh-keys.sh"

cat >"$CRON_SCRIPT" <<'EOF'
#!/bin/bash
USERNAME="admin"
GITHUB_USER="shubymao"
HOME_DIR="/home/$USERNAME"
AUTH_KEYS="$HOME_DIR/.ssh/authorized_keys"
TMP_FILE="/tmp/github_keys_$$.tmp"

fetch_github_keys() {
    curl -s "https://api.github.com/users/${GITHUB_USER}/keys" > "$TMP_FILE"
    
    if [ $? -ne 0 ]; then
        echo "Failed to fetch keys from GitHub API"
        rm -f "$TMP_FILE"
        exit 1
    fi

    while IFS= read -r line; do
        if echo "$line" | grep -q '"key"'; then
            key=$(echo "$line" | sed -E 's/.*"key"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | sed 's/\\n/\n/g')
            if [ -n "$key" ]; then
                if ! grep -qF "$key" "$AUTH_KEYS" 2>/dev/null; then
                    echo "$key" >> "$AUTH_KEYS"
                fi
            fi
        fi
    done < "$TMP_FILE"

    rm -f "$TMP_FILE"
    chown "$USERNAME:$USERNAME" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
}

fetch_github_keys
EOF

chmod +x "$CRON_SCRIPT"
chown root:root "$CRON_SCRIPT"

# 8. Setup cron job (runs every hour)
cat >"$CRON_JOB_FILE" <<EOF
0 * * * * root /usr/local/bin/sync-github-ssh-keys.sh
EOF

chmod 644 "$CRON_JOB_FILE"
systemctl restart cron 2>/dev/null || systemctl restart cron.service 2>/dev/null || true

echo "Cron job setup: syncs GitHub SSH keys every hour."

# Run the sync script once now
echo "Running initial GitHub SSH keys sync..."
/usr/local/bin/sync-github-ssh-keys.sh

echo ""
echo "Server initialization complete!"
echo "Admin user: $USERNAME"
echo "SSH keys from GitHub user '$GITHUB_USER' will be synced hourly."
