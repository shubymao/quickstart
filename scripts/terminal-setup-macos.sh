#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[quickstart] $*"
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

ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

ensure_brew_path_now() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_brew_pkg() {
  local pkg="$1"
  if brew list --versions "$pkg" >/dev/null 2>&1; then
    log "Package already installed: $pkg"
    return
  fi
  log "Installing package: $pkg"
  brew install "$pkg"
}

install_codex() {
  if command -v codex >/dev/null 2>&1; then
    log "OpenAI Codex already installed"
    return
  fi

  log "Installing OpenAI Codex via npm"
  if npm install -g @openai/codex; then
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
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "[quickstart][error] This script only supports macOS." >&2
    exit 1
  fi

  ensure_brew
  ensure_brew_path_now
  if ! command -v brew >/dev/null 2>&1; then
    echo "[quickstart][error] Homebrew is not available after installation." >&2
    exit 1
  fi
  brew update

  install_brew_pkg fish
  install_brew_pkg neovim
  install_brew_pkg vim
  install_brew_pkg node

  install_codex

  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  install_aliases "$repo_root"

  log "macOS terminal bootstrap completed."
}

main "$@"
