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

install_aliases() {
  local repo_root="$1"
  # Target path for Fish auto-loading configs
  local fish_conf_dir="$HOME/.config/fish/conf.d"
  # Source path based on your folder structure
  local source_fish_aliases="$repo_root/dotfiles/.config/fish/conf.d/aliases.fish"

  mkdir -p "$fish_conf_dir"

  if [[ -f "$source_fish_aliases" ]]; then
    cp -f "$source_fish_aliases" "$fish_conf_dir/aliases.fish"
    log "Success: Copied Fish aliases from $source_fish_aliases"
  else
    log "[error] Source aliases file not found at: $source_fish_aliases"
  fi

  # Ensure SSH directory exists with correct permissions
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
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
    echo "$fish_path" | sudo tee -a /etc/shells > /dev/null
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

  # Install Core Apps
  install_apt_pkg fish
  install_apt_pkg neovim
  install_apt_pkg nodejs
  install_apt_pkg npm

  # Install "Oxidized" Tools
  install_eza
  install_zoxide

  # Deploy Configs
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  install_aliases "$repo_root"

  # set fish as default shell
  set_fish_default

  log "Ubuntu terminal bootstrap completed."
  log "Please run 'fish' to enter your new shell."
}

main "$@"