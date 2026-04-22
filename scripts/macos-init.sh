#!/usr/bin/env bash
set -euo pipefail

write_step() {
  echo "[quickstart] $*"
}

warn_step() {
  echo "[quickstart][warn] $*" >&2
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "[quickstart][error] This script only supports macOS." >&2
    exit 1
  fi
}

get_install_profile() {
  echo
  echo "Choose install profile:"
  echo "1) Base only (recommended for non-dev machines)"
  echo "2) Dev (installs Base + Dev tools)"
  read -r -p "Enter choice [1/2]: " choice
  if [[ "$choice" == "2" ]]; then
    echo "Dev"
    return
  fi
  echo "BaseOnly"
}

ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  write_step "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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

brew_target_exists() {
  local kind="$1"
  local target="$2"

  if [[ "$kind" == "cask" ]]; then
    brew info --cask "$target" >/dev/null 2>&1
    return
  fi
  brew info "$target" >/dev/null 2>&1
}

brew_target_installed() {
  local kind="$1"
  local target="$2"

  if [[ "$kind" == "cask" ]]; then
    brew list --cask --versions "$target" >/dev/null 2>&1
    return
  fi
  brew list --versions "$target" >/dev/null 2>&1
}

install_brew_target() {
  local kind="$1"
  local target="$2"

  if brew_target_installed "$kind" "$target"; then
    write_step "Package already installed: $target"
    return 0
  fi

  write_step "Installing package: $target"
  if [[ "$kind" == "cask" ]]; then
    brew install --cask "$target"
    return
  fi
  brew install "$target"
}

resolve_first_available_target() {
  local kind="$1"
  local candidates_csv="$2"
  local candidate

  IFS=',' read -r -a candidates <<<"$candidates_csv"
  for candidate in "${candidates[@]}"; do
    if brew_target_exists "$kind" "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

install_app_entry() {
  local entry="$1"
  local name kind candidates target
  IFS='|' read -r name kind candidates <<<"$entry"

  if ! target="$(resolve_first_available_target "$kind" "$candidates")"; then
    warn_step "No Homebrew $kind candidate found for '$name' (tried: $candidates)"
    MISSING_APPS+=("$name")
    return 0
  fi

  if [[ "$target" == "virtualbox" && "$(uname -m)" == "arm64" ]]; then
    warn_step "VirtualBox on Apple Silicon can be limited/unsupported. If install fails, share preferred replacement."
  fi

  if ! install_brew_target "$kind" "$target"; then
    warn_step "Failed to install '$name' via target '$target'"
    FAILED_INSTALLS+=("$name ($target)")
  fi
}

install_nerd_fonts() {
  write_step "Installing Nerd Fonts: Meslo, FiraCode, SourceCodePro"
  brew tap homebrew/cask-fonts >/dev/null

  local fonts=(
    "font-meslo-lg-nerd-font"
    "font-fira-code-nerd-font"
    "font-source-code-pro-nerd-font"
  )

  local font
  for font in "${fonts[@]}"; do
    if ! install_brew_target "cask" "$font"; then
      warn_step "Failed to install font cask: $font"
    fi
  done
}

install_wezterm_config() {
  local repo_root="$1"
  local source="$repo_root/dotfiles/wezterm/.wezterm.lua"
  local target="$HOME/.wezterm.lua"

  if [[ ! -f "$source" ]]; then
    warn_step "WezTerm config not found: $source"
    return
  fi

  cp -f "$source" "$target"
  write_step "Installed WezTerm config to $target"
}

configure_karabiner() {
  local repo_root="$1"
  local source_cfg="$repo_root/dotfiles/karabiner/karabiner.json"
  local source_assets="$repo_root/dotfiles/karabiner/assets"
  local target_dir="$HOME/.config/karabiner"
  local target_assets="$target_dir/assets"

  write_step "Source: $source_cfg -> Target: $target_dir/karabiner.json"

  mkdir -p "$target_dir"
  if [[ -f "$source_cfg" ]]; then
    if cp -f "$source_cfg" "$target_dir/karabiner.json"; then
      write_step "Installed Karabiner config to $target_dir/karabiner.json"
    else
      warn_step "Failed to copy Karabiner config"
    fi
  else
    warn_step "Karabiner config not found: $source_cfg"
  fi

  if [[ -d "$source_assets" ]]; then
    write_step "Source: $source_assets/complex_modifications -> Target: $target_assets"
    mkdir -p "$target_assets"
    rm -rf "$target_assets/complex_modifications"
    if cp -R "$source_assets/complex_modifications" "$target_assets/"; then
      write_step "Installed Karabiner assets to $target_assets"
    else
      warn_step "Failed to copy Karabiner assets"
    fi
  fi
}

install_wallpapers() {
  local target_dir="$HOME/Pictures/quickstart-wallpapers"

  if [[ -d "$target_dir" ]] && [[ -n "$(ls -A "$target_dir" 2>/dev/null)" ]]; then
    write_step "Wallpapers already installed at $target_dir"
    find "$target_dir" -type f | head -n 1
    return 0
  fi

  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  if ! git clone --quiet https://github.com/shubymao/wallpaper.git "$target_dir"; then
    warn_step "Failed to clone wallpaper repo"
    rm -rf "$target_dir"
    return 1
  fi
  write_step "Cloned wallpapers to $target_dir"

  local first_image
  first_image="$(find "$target_dir" -type f | head -n 1 || true)"
  if [[ -n "$first_image" ]]; then
    echo "$first_image"
    return 0
  fi

  warn_step "No wallpaper files found in $target_dir"
  return 1
}

set_desktop_picture() {
  local image_path="$1"
  osascript <<EOF >/dev/null
tell application "Finder"
  set desktop picture to POSIX file "$image_path"
end tell
EOF
  write_step "Configured desktop wallpaper"
}

set_macos_dark_theme() {
  osascript -e \
    'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null
  write_step "Configured macOS dark theme (apps + system)"
}

ensure_dockutil() {
  if command -v dockutil >/dev/null 2>&1; then
    return
  fi
  install_brew_target "formula" "dockutil" || true
}

dock_has_item() {
  local label="$1"
  dockutil --find "$label" >/dev/null 2>&1
}

add_to_dock_if_present() {
  local label="$1"
  shift
  local app_path

  for app_path in "$@"; do
    if [[ -d "$app_path" ]]; then
      if dock_has_item "$label"; then
        return 0
      fi
      dockutil --add "$app_path" --position end --no-restart >/dev/null
      write_step "Pinned to Dock: $label"
      return 0
    fi
  done

  warn_step "Skipping Dock pin for $label: app not found"
  return 1
}

configure_dock_apps() {
  write_step "Pinning requested apps to Dock"
  ensure_dockutil
  if ! command -v dockutil >/dev/null 2>&1; then
    warn_step "dockutil is unavailable; skipping Dock pinning"
    return
  fi

  add_to_dock_if_present "Finder" \
    "/System/Library/CoreServices/Finder.app"
  add_to_dock_if_present "Terminal" \
    "/System/Applications/Utilities/Terminal.app"

  add_to_dock_if_present "WezTerm" \
    "/Applications/WezTerm.app" || true
  add_to_dock_if_present "Alacritty" \
    "/Applications/Alacritty.app"
  add_to_dock_if_present "Screenshot" \
    "/System/Applications/Utilities/Screenshot.app"
  add_to_dock_if_present "Calculator" \
    "/System/Applications/Calculator.app"
  add_to_dock_if_present "Browser" \
    "/Applications/Google Chrome.app" \
    "/Applications/Firefox.app" \
    "/Applications/Brave Browser.app" \
    "/Applications/Safari.app"
  add_to_dock_if_present "Google Chrome" \
    "/Applications/Google Chrome.app"
  add_to_dock_if_present "Raycast" \
    "/Applications/Raycast.app"

  killall Dock >/dev/null 2>&1 || true
}

install_fish_conf() {
  local repo_root="$1"
  local fish_conf_dir="$HOME/.config/fish/conf.d"
  local source_fish_config="$repo_root/dotfiles/.config/fish/conf.d/main.fish"

  write_step "Source: $source_fish_config -> Target: $fish_conf_dir/main.fish"

  mkdir -p "$fish_conf_dir"

  if [[ -f "$source_fish_config" ]]; then
    if cp -f "$source_fish_config" "$fish_conf_dir/main.fish"; then
      write_step "Installed Fish conf to $fish_conf_dir/main.fish"
    else
      warn_step "Failed to copy Fish conf"
    fi
  else
    warn_step "Fish conf not found: $source_fish_config"
  fi

  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
}

install_nvim_config() {
  local repo_root="$1"
  local nvim_conf_dir="$HOME/.config/nvim"
  local source_nvim_dir="$repo_root/dotfiles/.config/nvim"

  mkdir -p "$HOME/.config"

  if [[ -d "$source_nvim_dir" ]]; then
    rm -rf "$nvim_conf_dir"
    cp -rf "$source_nvim_dir" "$HOME/.config/"
    write_step "Installed Neovim config to $nvim_conf_dir"
    find "$nvim_conf_dir" -type d -exec chmod 755 {} +
    find "$nvim_conf_dir" -type f -exec chmod 644 {} +
  else
    warn_step "Neovim config not found: $source_nvim_dir"
  fi
}

install_tmux_conf() {
  local repo_root="$1"
  local source_tmux="$repo_root/dotfiles/tmux/.tmux.conf"
  local target_tmux="$HOME/.tmux.conf"

  if [[ -f "$source_tmux" ]]; then
    if [[ ! -f "$target_tmux" ]] || ! cmp -s "$source_tmux" "$target_tmux"; then
      cp -f "$source_tmux" "$target_tmux"
      write_step "Installed tmux config to $target_tmux"
    else
      write_step "Tmux config already up to date: $target_tmux"
    fi
  fi
}

install_tpm() {
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [[ -d "$tpm_dir" ]]; then
    write_step "tpm already installed"
    return
  fi
  write_step "Installing tmux plugin manager (tpm)..."
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
    write_step "Installed tmux sessionizer to $target_script"
  fi
}

check_ssh() {
  local key_path="$HOME/.ssh/id_ed25519"
  local pub_key_path="${key_path}.pub"

  if [ -f "$key_path" ]; then
    write_step "SSH key already exists: $key_path"
    return
  fi

  write_step "Generating SSH key..."
  read -r -p "Enter your GitHub email address: " user_email

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  ssh-keygen -t ed25519 -C "$user_email" -f "$key_path" -N ""

  write_step "SSH key generated successfully!"
  echo "-------------------------------------------------------"
  echo "Copy the text below and add it to GitHub Settings:"
  echo "-------------------------------------------------------"
  cat "$pub_key_path"
  echo "-------------------------------------------------------"
}

install_opencode() {
  if command -v opencode >/dev/null 2>&1; then
    write_step "OpenCode already installed"
    return
  fi
  write_step "Installing OpenCode CLI..."
  curl -fsSL https://opencode.ai/install | bash
}

set_fish_default() {
  local fish_path
  fish_path=$(command -v fish)

  if [ -z "$fish_path" ]; then
    warn_step "fish not found, cannot set as default."
    return 1
  fi

  if grep -qxF "$fish_path" /etc/shells; then
    :
  else
    write_step "Adding $fish_path to /etc/shells"
    echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
  fi

  local current_shell
  current_shell=$(getent passwd "$USER" | cut -d: -f7)

  if [[ "$current_shell" != "$fish_path" ]]; then
    write_step "Changing default shell to fish..."
    sudo chsh -s "$fish_path" "$USER"
  else
    write_step "Fish is already the default shell."
  fi
}

install_terminal_tools() {
  local repo_root="$1"

  write_step "Installing terminal tools via Homebrew..."

  install_brew_target "formula" "fish"
  install_brew_target "formula" "fzf"
  install_brew_target "formula" "eza"
  install_brew_target "formula" "zoxide"
  install_brew_target "formula" "neovim"
  install_brew_target "formula" "tmux"
  install_brew_target "formula" "node"
  install_brew_target "formula" "ripgrep"
  install_brew_target "formula" "fd"
  install_brew_target "formula" "tree-sitter-cli"
  install_brew_target "formula" "cmake"
  install_brew_target "formula" "ninja"

  if [[ -d "/opt/homebrew/Cellar/neovim" ]] || [[ -d "/usr/local/Cellar/neovim" ]]; then
    rm -rf ~/.local/share/nvim/luacache
    rm -rf ~/.local/state/nvim/lazy
  fi

  install_fish_conf "$repo_root"
  install_nvim_config "$repo_root"
  install_tmux_conf "$repo_root"
  install_tmux_sessionizer "$repo_root"
  install_tpm
  install_opencode
  check_ssh

  write_step "Setting fish as default shell..."
  set_fish_default || true

  write_step "Terminal tools installation completed."
}

main() {
  require_macos

  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  ensure_brew
  ensure_brew_path_now
  if ! command -v brew >/dev/null 2>&1; then
    echo "[quickstart][error] Homebrew is not available after installation." >&2
    exit 1
  fi

  brew update

  local install_profile
  install_profile="$(get_install_profile)"
  local is_dev_profile="false"
  if [[ "$install_profile" == "Dev" ]]; then
    is_dev_profile="true"
  fi

  write_step "Installing app packages for profile: $install_profile"

  local base_apps=(
    "Firefox|cask|firefox"
    "Google Chrome|cask|google-chrome"
    "Brave|cask|brave-browser"
    "7-Zip|formula|p7zip,sevenzip"
    "VLC|cask|vlc"
    "GIMP|cask|gimp"
    "Tailscale|cask|tailscale"
    "Nextcloud|cask|nextcloud"
    "Jellyfin Media Player|cask|jellyfin-media-player"
    "LibreOffice|cask|libreoffice"
  )

  local dev_apps=(
    "WezTerm|cask|wezterm"
    "Alacritty|cask|alacritty"
    "Karabiner-Elements|cask|karabiner-elements"
    "Raycast|cask|raycast"
    "Visual Studio Code|cask|visual-studio-code"
    "Joplin|cask|joplin"
    "Proton VPN|cask|protonvpn"
    "VirtualBox|cask|virtualbox"
    "Docker|cask|docker"
    "OrcaSlicer|cask|orca-slicer"
    "MusicBrainz Picard|cask|musicbrainz-picard"
    "Tag Editor|cask|tageditor"
  )

  local entry
  for entry in "${base_apps[@]}"; do
    install_app_entry "$entry"
  done
  for entry in "${dev_apps[@]}"; do
      install_app_entry "$entry"
  done
  install_terminal_tools "$repo_root"

  set_macos_dark_theme

  install_wezterm_config "$repo_root"
  configure_karabiner "$repo_root"

  configure_dock_apps

  write_step "macOS desktop bootstrap completed."

  if [[ "${#MISSING_APPS[@]}" -gt 0 ]]; then
    warn_step "No macOS Homebrew target found for: ${MISSING_APPS[*]}"
    warn_step "Send replacements for those apps and I can map them."
  fi
  if [[ "${#FAILED_INSTALLS[@]}" -gt 0 ]]; then
    warn_step "Install failed for: ${FAILED_INSTALLS[*]}"
  fi
}

MISSING_APPS=()
FAILED_INSTALLS=()
main "$@"
