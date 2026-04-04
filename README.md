
# Shuby Mao's quickstart

Quickly initialize key setup and environment in order to start being productive
## Clone Repo

```
git clone https://github.com/shubymao/quickstart.git
```

To change the https to ssh version (to allow edit and pushing) run
```
git remote set-url origin git@github.com:shubymao/quickstart.git
```


## Inventory Node Setup 
## Control Node Setup
### Install ansible-playbook

```
python3 -m pip install --user ansible
```

### Add ansible to path

```
export PATH=$PATH:/home/{your_user_name}/.local/bin
```
Before you run, you should have make sure you are in your own user (and not root).

To run simply, run
```
ansible-playbook -K --ask-vault-pass universal.yml
```

To run a particular tag use the -t command. E.g
```
ansible-playbook -t nvim universal.yml
```

## Windows Quick Setup

From an elevated PowerShell (Run as Administrator), run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\universal.ps1
```

The script prompts at startup for:
- `BaseOnly`: base apps only
- `Dev`: base + dev tools

`Base` apps are always installed regardless of profile.

What this installs/configures:
- Base: Firefox, Brave, 7-Zip, VLC, GIMP, PDFgear, Tailscale, Nextcloud, Jellyfin, LibreOffice
- Nerd Fonts (latest release): Meslo, FiraCode, SourceCodePro
- Dev: WezTerm, Alacritty, VS Code, WSL (default version 2 + Ubuntu distro), Joplin, AutoHotkey v2
- WezTerm config from `dotfiles/wezterm/.wezterm.lua` to `%USERPROFILE%\.wezterm.lua` (Dev profile)
- Startup shortcut for `dotfiles/main.ahk` (Dev profile)
- Clones wallpapers from `https://github.com/shubymao/wallpaper.git` to `%USERPROFILE%\Pictures\quickstart-wallpapers`
- Sets desktop wallpaper to slideshow from that folder
- Tries to set lock screen image to the first wallpaper file
- Sets Windows apps/system theme to dark
- Adds Desktop shortcuts for File Explorer, PowerShell, WezTerm, Alacritty, Snipping Tool, Calculator, and Browser
- Tries to pin the same apps to the taskbar

Optional distro override:

```powershell
.\universal.ps1 -WslDistro "Ubuntu-24.04"
```

## Raycast Windows

Backup and restore Raycast settings using the built-in export/import commands.

### Backup

1. Open Raycast (`Alt + Space`)
2. Run **Export Settings & Data**
3. Set a passphrase (stored in Settings → Raycast)
4. Saves as `.rayconfig` file

### Restore

1. Copy `.rayconfig` to Downloads folder
2. Run **Import Settings & Data**
3. Select the file and enter passphrase

The export includes: quicklinks, snippets, settings, extensions, hotkeys, and aliases.

### Config Location

Raycast Windows doesn't store config in a manual location. Use the export/import commands above. The backed-up config is stored in `dotfiles/raycast/raycast.rayconfig`.

## Fedora Desktop Quick Setup

Run from your normal user (the script uses `sudo` for package installs):

```bash
chmod +x ./fedora-init.sh
./fedora-init.sh
```

The script prompts at startup for:
- `BaseOnly`: base apps only
- `Dev`: base + dev tools

What this installs/configures:
- Base apps: Firefox, VLC, GIMP, LibreOffice, Nextcloud client, Tailscale, 7zip tools, Evince
- Nerd Fonts (latest release): Meslo, FiraCode, SourceCodePro
- Base Flatpak apps: Jellyfin Media Player
- Dev apps: WezTerm, Alacritty, keyd (for key remapping)
- Dev Flatpak apps: VS Code, Joplin, Proton VPN, VirtualBox (when available on Flathub)
- WezTerm config from `dotfiles/wezterm/.wezterm.lua` to `~/.wezterm.lua` (Dev profile)
- Clones wallpapers from `https://github.com/shubymao/wallpaper.git` to `~/Pictures/quickstart-wallpapers`
- Sets GNOME wallpaper to the first copied image
- Adds app launchers to GNOME favorites (taskbar/dock)
- Sets GNOME custom hotkeys (Dev profile):
  - `Ctrl+Alt+T`: terminal (Alacritty if installed)
  - `Ctrl+Alt+B`: open browser
- Sets key remapping with `keyd` (Dev profile):
  - `CapsLock -> Esc`
  - `RightAlt + H/J/K/L` as arrow keys

## Universal Terminal Setup (Ubuntu/Fedora/macOS)

Use one entry script that dispatches to OS-specific setup:

```bash
chmod +x ./universal.sh
./universal.sh
```

What it sets up:
- Installs terminal/editor tools with the correct package manager per OS:
  - Ubuntu: `apt`
  - Fedora: `dnf`
  - macOS: installs Homebrew if missing, then uses `brew`
- Installs: `fish`, `neovim`, `vim` (backup), `node/npm`, and OpenAI Codex (`@openai/codex`) and `fzf`
- Installs aliases:
  - Copies `dotfiles/.aliases` to `~/.aliases`
  - Ensures `~/.bashrc` and `~/.zshrc` source `~/.aliases`
  - Creates fish aliases at `~/.config/fish/conf.d/quickstart_aliases.fish`
  - Copies `dotfiles/tmux/.tmux.conf` to `~/.tmux.conf`
  - Installs `tmux_sessionizer` script to `~/.local/bin/tmux_sessionizer`
  - Fish binds `Ctrl+f` to launch the tmux sessionizer

OS-specific scripts:
- `scripts/terminal-setup-ubuntu.sh`
- `scripts/terminal-setup-fedora.sh`
- `scripts/terminal-setup-macos.sh`

## First-Time Server Bootstrap

### Quick Run (One-Liner)

Run directly from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/shubymao/quickstart/main/scripts/server-init.sh -o /tmp/server-init.sh && sudo bash /tmp/server-init.sh && rm /tmp/server-init.sh
```

### Local Run

1. Bootstrap user + SSH key (keeps password auth enabled):

```bash
sudo ./server-init.sh
```

2. After confirming key login works, harden SSH:

```bash
sudo ./server-init.sh --harden-ssh
```

### What It Does

- Prompts for admin password (creates `admin` user if missing)
- Installs `sudo` if missing
- Adds admin to sudo group
- Installs and starts SSH
- Hardens SSH: disables root login and password auth, enables pubkey auth
- Disables root account entirely (locked + no shell)
- Sets up hourly cron job syncing SSH keys from GitHub user `shubymao`
