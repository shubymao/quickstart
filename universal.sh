#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

detect_os_script() {
  local uname_s
  uname_s="$(uname -s)"

  if [[ "$uname_s" == "Darwin" ]]; then
    echo "$repo_root/scripts/terminal-setup-macos.sh"
    return 0
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu)
        echo "$repo_root/scripts/terminal-setup-ubuntu.sh"
        return 0
        ;;
      fedora)
        echo "$repo_root/scripts/terminal-setup-fedora.sh"
        return 0
        ;;
    esac
  fi

  return 1
}

main() {
  local target
  if ! target="$(detect_os_script)"; then
    echo "[quickstart][error] Unsupported OS. Supported: Ubuntu, Fedora, macOS." >&2
    exit 1
  fi

  if [[ ! -x "$target" ]]; then
    chmod +x "$target"
  fi

  exec "$target" "$@"
}

main "$@"
