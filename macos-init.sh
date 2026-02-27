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

  mkdir -p "$target_dir"
  if [[ -f "$source_cfg" ]]; then
    cp -f "$source_cfg" "$target_dir/karabiner.json"
    write_step "Installed Karabiner config to $target_dir/karabiner.json"
  else
    warn_step "Karabiner config not found: $source_cfg"
  fi

  if [[ -d "$source_assets" ]]; then
    mkdir -p "$target_assets"
    rm -rf "$target_assets/complex_modifications"
    cp -R "$source_assets/complex_modifications" "$target_assets/"
    write_step "Installed Karabiner assets to $target_assets"
  fi
}

install_wallpapers() {
  local repo_root="$1"
  local source_dir="$repo_root/wallpapers"
  local target_dir="$HOME/Pictures/quickstart-wallpapers"

  if [[ ! -d "$source_dir" ]]; then
    warn_step "Wallpaper source directory not found: $source_dir"
    return 1
  fi

  mkdir -p "$target_dir"
  cp -f "$source_dir"/* "$target_dir"/
  write_step "Copied wallpapers to $target_dir"

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
    "/Applications/WezTerm.app"
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

main() {
  require_macos

  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    "PDFgear|cask|pdfgear"
    "Tailscale|cask|tailscale"
    "Nextcloud|cask|nextcloud"
    "Jellyfin Media Player|cask|jellyfin-media-player"
    "LibreOffice|cask|libreoffice"
  )
  local dev_apps=(
    "WezTerm|cask|wezterm"
    "Alacritty|cask|alacritty"
    "Visual Studio Code|cask|visual-studio-code"
    "Joplin|cask|joplin"
    "Proton VPN|cask|protonvpn"
    "VirtualBox|cask|virtualbox"
    "Karabiner-Elements|cask|karabiner-elements"
    "Raycast|cask|raycast"
  )

  local entry
  for entry in "${base_apps[@]}"; do
    install_app_entry "$entry"
  done
  if [[ "$is_dev_profile" == "true" ]]; then
    for entry in "${dev_apps[@]}"; do
      install_app_entry "$entry"
    done
  fi

  install_nerd_fonts

  if [[ "$is_dev_profile" == "true" ]]; then
    install_wezterm_config "$repo_root"
    configure_karabiner "$repo_root"
  fi

  local first_wallpaper
  if first_wallpaper="$(install_wallpapers "$repo_root")"; then
    set_desktop_picture "$first_wallpaper"
  fi

  set_macos_dark_theme
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
