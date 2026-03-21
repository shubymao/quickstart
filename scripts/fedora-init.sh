#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[quickstart] $*" >&2
}

warn() {
  echo "[quickstart][warn] $*" >&2
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[quickstart][error] Required command '$cmd' was not found." >&2
    exit 1
  fi
}

choose_install_profile() {
  echo
  echo "Choose install profile:"
  echo "1) Base only (recommended for non-dev machines)"
  echo "2) Dev (installs Base + Dev tools)"
  read -r -p "Enter choice [1/2]: " choice
  if [[ "$choice" == "2" ]]; then
    echo "Dev"
  else
    echo "BaseOnly"
  fi
}

install_dnf_package() {
  local pkg="$1"
  if rpm -q "$pkg" >/dev/null 2>&1; then
    log "Package already installed: $pkg"
    return
  fi
  log "Installing package: $pkg"
  sudo dnf install -y "$pkg"
}

ensure_flathub_remote() {
  if ! command -v flatpak >/dev/null 2>&1; then
    return
  fi
  if flatpak remote-list --columns=name | grep -Fxq "flathub"; then
    return
  fi
  log "Adding flathub remote"
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

install_flatpak_app() {
  local app_id="$1"
  if ! command -v flatpak >/dev/null 2>&1; then
    warn "flatpak not found, skipping app: $app_id"
    return
  fi
  if flatpak info "$app_id" >/dev/null 2>&1; then
    log "Flatpak app already installed: $app_id"
    return
  fi
  log "Installing flatpak app: $app_id"
  if ! flatpak install -y flathub "$app_id"; then
    warn "Unable to install flatpak app: $app_id"
  fi
}

install_nerd_fonts() {
  local fonts=("Meslo" "FiraCode" "SourceCodePro")
  local font_dir="$HOME/.local/share/fonts"
  local cache_dir="$HOME/.cache/quickstart-nerd-fonts"
  local needs_fc_cache=0

  mkdir -p "$font_dir" "$cache_dir"
  require_command curl
  require_command unzip

  local font
  for font in "${fonts[@]}"; do
    if find "$font_dir" -maxdepth 1 -type f -iname "*$font*Nerd*Font*.ttf" | grep -q .; then
      log "Nerd Font already installed: $font"
      continue
    fi

    local zip_path="$cache_dir/${font}.zip"
    local extract_dir="$cache_dir/${font}"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"

    log "Downloading Nerd Font pack: $font"
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip" -o "$zip_path"
    unzip -o -q "$zip_path" -d "$extract_dir"

    local copied=0
    local font_file
    while IFS= read -r font_file; do
      cp -f "$font_file" "$font_dir/"
      copied=1
    done < <(find "$extract_dir" -type f \( -iname "*.ttf" -o -iname "*.otf" \))

    if [[ "$copied" -eq 1 ]]; then
      log "Installed Nerd Font pack: $font"
      needs_fc_cache=1
    else
      warn "No font files found in pack: $font"
    fi
  done

  if [[ "$needs_fc_cache" -eq 1 ]] && command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$font_dir" >/dev/null 2>&1 || true
    log "Rebuilt font cache"
  fi
}

install_wallpapers() {
  local target_dir="$HOME/Pictures/quickstart-wallpapers"
  if [[ -d "$target_dir" ]] && [[ -n "$(ls -A "$target_dir" 2>/dev/null)" ]]; then
    log "Wallpapers already installed at $target_dir"
    find "$target_dir" -maxdepth 1 -type f | sort | head -n 1
    return
  fi

  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  if ! git clone --quiet https://github.com/shubymao/wallpaper.git "$target_dir"; then
    echo "[quickstart][error] Failed to clone wallpaper repo" >&2
    rm -rf "$target_dir"
    exit 1
  fi
  log "Cloned wallpapers to $target_dir"

  local first_image
  first_image="$(find "$target_dir" -maxdepth 1 -type f | sort | head -n 1 || true)"
  echo "$first_image"
}

set_gnome_wallpaper() {
  local image_path="$1"
  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings not found, skipping wallpaper setup"
    return
  fi
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    warn "No active graphical session detected, skipping wallpaper setup"
    return
  fi

  local uri="file://$image_path"
  gsettings set org.gnome.desktop.background picture-uri "$uri"
  gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
  gsettings set org.gnome.desktop.background picture-options "zoom"
  log "Configured GNOME desktop wallpaper"
}

desktop_entry_exists() {
  local entry="$1"
  [[ -f "/usr/share/applications/$entry" ]] \
    || [[ -f "/var/lib/flatpak/exports/share/applications/$entry" ]] \
    || [[ -f "$HOME/.local/share/flatpak/exports/share/applications/$entry" ]]
}

resolve_desktop_entry() {
  local candidate
  for candidate in "$@"; do
    if desktop_entry_exists "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

set_gnome_favorites() {
  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings not found, skipping favorites setup"
    return
  fi
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    warn "No active graphical session detected, skipping favorites setup"
    return
  fi

  local desired=()
  local entry

  entry="$(resolve_desktop_entry org.gnome.Nautilus.desktop nautilus.desktop || true)"
  [[ -n "$entry" ]] && desired+=("$entry")
  entry="$(resolve_desktop_entry org.gnome.Terminal.desktop gnome-terminal.desktop || true)"
  [[ -n "$entry" ]] && desired+=("$entry")
  entry="$(resolve_desktop_entry firefox.desktop org.mozilla.firefox.desktop || true)"
  [[ -n "$entry" ]] && desired+=("$entry")
  entry="$(resolve_desktop_entry org.wezfurlong.wezterm.desktop wezterm.desktop || true)"
  [[ -n "$entry" ]] && desired+=("$entry")
  entry="$(resolve_desktop_entry Alacritty.desktop alacritty.desktop || true)"
  [[ -n "$entry" ]] && desired+=("$entry")
  entry="$(resolve_desktop_entry com.visualstudio.code.desktop com.vscodium.codium.desktop || true)"
  [[ -n "$entry" ]] && desired+=("$entry")
  entry="$(resolve_desktop_entry net.cozic.joplin_desktop.desktop || true)"
  [[ -n "$entry" ]] && desired+=("$entry")
  entry="$(resolve_desktop_entry org.gnome.Calculator.desktop gnome-calculator.desktop || true)"
  [[ -n "$entry" ]] && desired+=("$entry")

  if [[ "${#desired[@]}" -eq 0 ]]; then
    warn "No desktop entries found for favorites setup"
    return
  fi

  local current_raw
  current_raw="$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || echo "[]")"
  local existing=()
  while IFS= read -r token; do
    token="${token#"${token%%[![:space:]]*}"}"
    token="${token%"${token##*[![:space:]]}"}"
    [[ -n "$token" ]] && existing+=("$token")
  done < <(echo "$current_raw" | tr -d "[]'" | tr ',' '\n')

  local merged=()
  local item
  for item in "${existing[@]}" "${desired[@]}"; do
    [[ -z "$item" ]] && continue
    local seen=0
    local m
    for m in "${merged[@]}"; do
      if [[ "$m" == "$item" ]]; then
        seen=1
        break
      fi
    done
    if [[ "$seen" -eq 0 ]]; then
      merged+=("$item")
    fi
  done

  local gsettings_list="["
  local i
  for i in "${!merged[@]}"; do
    [[ "$i" -gt 0 ]] && gsettings_list+=", "
    gsettings_list+="'${merged[$i]}'"
  done
  gsettings_list+="]"

  gsettings set org.gnome.shell favorite-apps "$gsettings_list"
  log "Configured GNOME favorites (taskbar/dock)"
}

configure_gnome_hotkeys() {
  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings not found, skipping hotkey setup"
    return
  fi
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    warn "No active graphical session detected, skipping hotkey setup"
    return
  fi

  local terminal_cmd="gnome-terminal"
  if command -v alacritty >/dev/null 2>&1; then
    terminal_cmd="alacritty"
  fi

  local k1="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/quickstart-terminal/"
  local k2="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/quickstart-browser/"
  local key_root="org.gnome.settings-daemon.plugins.media-keys"

  gsettings set "$key_root" custom-keybindings "['$k1', '$k2']"

  gsettings set "${key_root}.custom-keybinding:${k1}" name "Quickstart Terminal"
  gsettings set "${key_root}.custom-keybinding:${k1}" command "$terminal_cmd"
  gsettings set "${key_root}.custom-keybinding:${k1}" binding "<Ctrl><Alt>t"

  gsettings set "${key_root}.custom-keybinding:${k2}" name "Quickstart Browser"
  gsettings set "${key_root}.custom-keybinding:${k2}" command "xdg-open https://www.google.com"
  gsettings set "${key_root}.custom-keybinding:${k2}" binding "<Ctrl><Alt>b"

  log "Configured GNOME custom hotkeys"
}

configure_keyd_remap() {
  local conf="/etc/keyd/default.conf"
  local tmp_file
  tmp_file="$(mktemp)"

  cat >"$tmp_file" <<'EOF'
[ids]
*

[main]
capslock = esc
rightalt = layer(nav)

[nav]
h = left
j = down
k = up
l = right
EOF

  local changed=0
  if [[ ! -f "$conf" ]]; then
    changed=1
  elif ! sudo cmp -s "$tmp_file" "$conf"; then
    changed=1
  fi

  if [[ "$changed" -eq 1 ]]; then
    sudo install -Dm644 "$tmp_file" "$conf"
    log "Installed key remap config at $conf"
  else
    log "Key remap config already up to date: $conf"
  fi
  rm -f "$tmp_file"

  if systemctl list-unit-files | grep -q '^keyd.service'; then
    sudo systemctl enable --now keyd
    if [[ "$changed" -eq 1 ]]; then
      sudo systemctl restart keyd
    fi
    log "Enabled keyd service"
  else
    warn "keyd service not found, skipping service enablement"
  fi
}

install_wezterm_config() {
  local repo_root="$1"
  local source="$repo_root/dotfiles/wezterm/.wezterm.lua"
  if [[ ! -f "$source" ]]; then
    warn "WezTerm config not found: $source"
    return
  fi
  cp -f "$source" "$HOME/.wezterm.lua"
  log "Installed WezTerm config to $HOME/.wezterm.lua"
}

main() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "[quickstart][error] Run this script as your normal user, not root." >&2
    exit 1
  fi

  require_command sudo
  require_command dnf
  sudo -v

  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local profile
  profile="$(choose_install_profile)"
  local is_dev=0
  [[ "$profile" == "Dev" ]] && is_dev=1
  log "Installing app packages for profile: $profile"

  local base_dnf=(
    firefox
    vlc
    gimp
    libreoffice
    nextcloud-client
    tailscale
    p7zip
    p7zip-plugins
    evince
    flatpak
    unzip
    fontconfig
    curl
  )
  local dev_dnf=(
    wezterm
    alacritty
    keyd
  )

  local base_flatpak=(
    org.jellyfin.JellyfinMediaPlayer
  )
  local dev_flatpak=(
    com.visualstudio.code
    net.cozic.joplin_desktop
    com.protonvpn.www
    org.virtualbox.VirtualBox
  )

  local pkg
  for pkg in "${base_dnf[@]}"; do
    install_dnf_package "$pkg"
  done
  if [[ "$is_dev" -eq 1 ]]; then
    for pkg in "${dev_dnf[@]}"; do
      install_dnf_package "$pkg"
    done
  fi

  ensure_flathub_remote
  local app
  for app in "${base_flatpak[@]}"; do
    install_flatpak_app "$app"
  done
  if [[ "$is_dev" -eq 1 ]]; then
    for app in "${dev_flatpak[@]}"; do
      install_flatpak_app "$app"
    done
  fi

  install_nerd_fonts

  if [[ "$is_dev" -eq 1 ]]; then
    install_wezterm_config "$repo_root"
    configure_keyd_remap
    configure_gnome_hotkeys
  fi

  local first_image
  first_image="$(install_wallpapers "$repo_root")"
  set_gnome_wallpaper "$first_image"
  set_gnome_favorites

  log "Fedora desktop bootstrap completed."
}

main "$@"
