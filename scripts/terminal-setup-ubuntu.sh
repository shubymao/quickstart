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

ensure_source_line() {
  local file="$1"
  local line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -Fqx "$line" "$file"; then
    printf "\n%s\n" "$line" >>"$file"
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

install_codex() {
  if command -v codex >/dev/null 2>&1; then
    log "OpenAI Codex already installed"
    return
  fi

  log "Installing OpenAI Codex via npm"
  if sudo npm install -g @openai/codex; then
    return
  fi
  echo "[quickstart][warn] Failed to install '@openai/codex' via npm." >&2
}

install_aliases() {
  local repo_root="$1"
  local source_aliases="$repo_root/dotfiles/.aliases"
  local target_aliases="$HOME/.aliases"
  local include_line='[ -f "$HOME/.aliases" ] && . "$HOME/.aliases"'

  if [[ -f "$source_aliases" ]]; then
    if [[ ! -f "$target_aliases" ]] || ! cmp -s "$source_aliases" "$target_aliases"; then
      cp -f "$source_aliases" "$target_aliases"
      log "Installed aliases to $target_aliases"
    else
      log "Aliases already up to date: $target_aliases"
    fi
  fi

  ensure_source_line "$HOME/.bashrc" "$include_line"
  ensure_source_line "$HOME/.zshrc" "$include_line"

  mkdir -p "$HOME/.config/fish/conf.d"
  cat >"$HOME/.config/fish/conf.d/quickstart_aliases.fish" <<'EOF'
alias v "nvim"
alias c "clear"
alias gs "git status"
alias ga "git add -A"
alias gcm "git commit -am"
alias gpl "git pull origin"
alias gpo "git push origin"
EOF
  log "Installed fish aliases"
}

main() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "[quickstart][error] Run as normal user. This script uses sudo when needed." >&2
    exit 1
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      echo "[quickstart][error] This script only supports Ubuntu." >&2
      exit 1
    fi
  fi

  require_cmd sudo
  require_cmd apt-get
  sudo -v
  sudo apt-get update -y

  install_apt_pkg fish
  install_apt_pkg neovim
  install_apt_pkg vim
  install_apt_pkg nodejs
  install_apt_pkg npm

  install_codex

  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  install_aliases "$repo_root"

  log "Ubuntu terminal bootstrap completed."
}

main "$@"
