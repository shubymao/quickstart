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

install_dnf_pkg() {
  local pkg="$1"
  if rpm -q "$pkg" >/dev/null 2>&1; then
    log "Package already installed: $pkg"
    return
  fi
  log "Installing package: $pkg"
  sudo dnf install -y "$pkg"
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

install_tmux_conf() {
  local repo_root="$1"
  local source_tmux="$repo_root/dotfiles/tmux/.tmux.conf"
  local target_tmux="$HOME/.tmux.conf"

  if [[ -f "$source_tmux" ]]; then
    if [[ ! -f "$target_tmux" ]] || ! cmp -s "$source_tmux" "$target_tmux"; then
      cp -f "$source_tmux" "$target_tmux"
      log "Installed tmux config to $target_tmux"
    else
      log "Tmux config already up to date: $target_tmux"
    fi
  fi
}

install_tpm() {
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [[ -d "$tpm_dir" ]]; then
    log "tpm already installed"
    return
  fi
  log "Installing tmux plugin manager (tpm)..."
  git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
}

install_tmux_sessionizer() {
  local repo_root="$1"
  local source_script="$repo_root/scripts/tmux_sessionizer"
  local target_script="$HOME/.local/bin/tmux_sessionizer"

  mkdir -p "$HOME/.local/bin"
  if [[ -f "$source_script" ]]; then
    cp -f "$source_script" "$target_script"
    chmod +x "$target_script"
    log "Installed tmux sessionizer to $target_script"
  fi
}

main() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "[quickstart][error] Run as normal user. This script uses sudo when needed." >&2
    exit 1
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "fedora" ]]; then
      echo "[quickstart][error] This script only supports Fedora." >&2
      exit 1
    fi
  fi

  require_cmd sudo
  require_cmd dnf
  sudo -v

  install_dnf_pkg fish
  install_dnf_pkg fzf
  install_dnf_pkg neovim
  install_dnf_pkg vim-enhanced
  install_dnf_pkg nodejs
  install_dnf_pkg npm

  install_codex

  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  install_aliases "$repo_root"
  install_tmux_conf "$repo_root"
  install_tmux_sessionizer "$repo_root"
  install_tpm

  log "Fedora terminal bootstrap completed."
}

main "$@"
