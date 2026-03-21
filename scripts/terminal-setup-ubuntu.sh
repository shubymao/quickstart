#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[quickstart] $*"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[quickstart][error] Required command '$cmd' is missing." >&2
    exit 1
  fi
}

install_apt_pkg() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    log "Package already installed: $pkg"
    return
  fi
  log "Installing package: $pkg"
  sudo apt-get install -y "$pkg"
}

install_neovim_from_source() {
  if command -v nvim >/dev/null 2>&1; then
    local version
    version=$(nvim --version | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    # Check if version is at least 0.11.2
    if [[ "$version" > "0.11.1" ]]; then
      log "Neovim $version already installed (meets >= 0.11.2 requirement)."
      return
    fi
  fi

  log "Building Neovim from source (Stable branch)..."

  # Build dependencies
  sudo apt-get install -y \
    ninja-build gettext libtool libtool-bin \
    autoconf automake cmake g++ pkg-config unzip curl

  local build_dir="$HOME/neovim-build"
  mkdir -p "$build_dir"
  cd "$build_dir"

  if [[ -d "neovim" ]]; then
    cd neovim
    git fetch --all
    git checkout stable
    git pull origin stable
    make distclean
  else
    git clone https://github.com/neovim/neovim.git
    cd neovim
    git checkout stable
  fi

  make CMAKE_BUILD_TYPE=RelWithDebInfo
  sudo make install

  # Clear stale Lua cache/state to prevent Snacks/Lualine errors
  rm -rf ~/.local/share/nvim/luacache
  rm -rf ~/.local/state/nvim/lazy

  log "Success: Neovim installed from source."
}

install_eza() {
  if command -v eza >/dev/null 2>&1; then
    log "eza already installed"
    return
  fi
  log "Installing eza (Rust-based ls)..."
  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
  sudo apt-get update
  sudo apt-get install -y eza
}

install_zoxide() {
  if command -v zoxide >/dev/null 2>&1; then
    log "zoxide already installed"
    return
  fi
  log "Installing zoxide (Rust-based cd)..."
  curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
}

install_opencode() {
  echo "Starting OpenCode CLI installation..."

  # Update and install dependencies
  sudo apt update && sudo apt install -y curl

  # Run the official installer
  curl -fsSL https://opencode.ai/install | bash

  # Refresh PATH in the current session
  if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
  fi

  # Verify installation
  if command -v opencode &>/dev/null; then
    echo "Successfully installed OpenCode CLI!"
    opencode --version
  else
    echo "Error: Installation failed or 'opencode' is not in your PATH."
    echo "Try running: source ~/.bashrc"
  fi
}

install_fish_conf() {
  local repo_root="$1"
  # Target path for Fish auto-loading configs
  local fish_conf_dir="$HOME/.config/fish/conf.d"
  # Source path based on your folder structure
  local source_fish_config="$repo_root/dotfiles/.config/fish/conf.d/main.fish"

  mkdir -p "$fish_conf_dir"

  if [[ -f "$source_fish_config" ]]; then
    cp -f "$source_fish_config" "$fish_conf_dir/main.fish"
    log "Success: Copied Fish conf from $source_fish_config"
  else
    log "[error] Source fish conf file not found at: $source_fish_config"
  fi

  # Ensure SSH directory exists with correct permissions
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
}

install_nvim_config() {
  local repo_root="$1"
  # Target path for Neovim config
  local nvim_conf_dir="$HOME/.config/nvim"
  # Source path based on your folder structure
  local source_nvim_dir="$repo_root/dotfiles/.config/nvim"

  # Ensure the parent .config directory exists
  mkdir -p "$HOME/.config"

  if [[ -d "$source_nvim_dir" ]]; then
    # Remove existing config to ensure a clean sync (optional but recommended)
    rm -rf "$nvim_conf_dir"

    # Copy the directory recursively
    cp -rf "$source_nvim_dir" "$HOME/.config/"

    log "Success: Copied Neovim configuration from $source_nvim_dir"

    # Fix permissions (standard 755 for dirs, 644 for files is typical)
    find "$nvim_conf_dir" -type d -exec chmod 755 {} +
    find "$nvim_conf_dir" -type f -exec chmod 644 {} +
  else
    log "[error] Source Neovim directory not found at: $source_nvim_dir"
  fi
}

check_ssh() {
  # Define the path to the default Ed25519 key
  local key_path="$HOME/.ssh/id_ed25519"
  local pub_key_path="${key_path}.pub"

  if [ -f "$key_path" ]; then
    echo "✅ SSH key already exists at: $key_path"
  else
    echo "❌ No SSH key found. Starting generation process..."

    # Prompt the user for their email
    read -p "Enter your GitHub email address: " user_email

    # Ensure the .ssh directory exists
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Generate the key
    # -t ed25519: specifies the type
    # -C: adds the email label
    # -f: saves to the standard path
    # -N "": sets an empty passphrase (remove this if you want to be prompted for a password)
    ssh_keygen_cmd="ssh-keygen -t ed25519 -C \"$user_email\" -f \"$key_path\" -N \"\""
    eval $ssh_keygen_cmd

    echo "🚀 Key generated successfully!"
  fi

  # Display the public key for the user to copy
  echo "-------------------------------------------------------"
  echo "Copy the text below and add it to GitHub Settings:"
  echo "-------------------------------------------------------"
  cat "$pub_key_path"
  echo "-------------------------------------------------------"
}

set_fish_default() {
  export PATH="$HOME/.local/bin:$PATH"
  local fish_path
  fish_path=$(command -v fish)

  if [ -z "$fish_path" ]; then
    log "[error] fish not found, cannot set as default."
    return 1
  fi

  # 1. Ensure fish is a valid shell in /etc/shells
  if ! grep -qxF "$fish_path" /etc/shells; then
    log "Adding $fish_path to /etc/shells"
    echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
  fi

  # 2. Check the current user's shell in /etc/passwd
  local current_shell
  current_shell=$(getent passwd "$USER" | cut -d: -f7)

  if [[ "$current_shell" != "$fish_path" ]]; then
    log "Changing default shell to $fish_path..."
    # Using sudo with chsh avoids the interactive password prompt in many Ubuntu configs
    sudo chsh -s "$fish_path" "$USER"
  else
    log "Fish is already the default shell."
  fi
}

main() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "[quickstart][error] Run as normal user. Script uses sudo when needed." >&2
    exit 1
  fi

  # Verify Ubuntu
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      echo "[quickstart][error] This script only supports Ubuntu." >&2
      exit 1
    fi
  fi

  require_cmd sudo
  require_cmd apt-get
  require_cmd wget
  require_cmd curl
  require_cmd gpg

  sudo -v
  sudo apt-get update -y

  check_ssh
  # Install Core Apps
  install_apt_pkg fish

  # Install Neovim (Source build ensures version >= 0.11.2)
  install_apt_pkg build-essential
  install_neovim_from_source

  install_apt_pkg nodejs
  install_apt_pkg npm
  install_apt_pkg python3.12-venv

  export PATH="$HOME/.local/bin:$PATH"
  # required for neovim
  sudo npm install -g tree-sitter-cli
  # 1. The Core (Compiling Parsers)
  install_apt_pkg libstdc++6 # Critical for C++ based parsers

  # 2. Retrieval & Extraction (Downloading Parsers)
  install_apt_pkg curl  # Fetching plugin/parser data
  install_apt_pkg git   # Cloning plugin repos
  install_apt_pkg unzip # Treesitter uses this to unpack grammars
  install_apt_pkg tar   # Alternative unpacking method
  install_apt_pkg gzip  # Common compression utility

  # 3. Neovim Build & Helper Tools (LSP/Mason Dependencies)
  install_apt_pkg cmake       # Often needed to build specialized LSPs
  install_apt_pkg gettext     # Required if you ever build Neovim from source
  install_apt_pkg ninja-build # Fast build system often used by Mason plugins

  # 4. Optional but Highly Recommended for WSL
  install_apt_pkg ripgrep # Essential for Telescope (Searching files)
  install_apt_pkg fd-find # Essential for Telescope (Finding files)

  # Install "Oxidized" Tools
  install_eza
  install_zoxide

  # Deploy Configs
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  install_fish_conf "$repo_root"
  install_nvim_config "$repo_root"
  install_opencode
  # set fish as default shell
  set_fish_default

  log "Ubuntu terminal bootstrap completed."
  log "Please run 'fish' to enter your new shell."
}

main "$@"
