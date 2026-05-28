#!/usr/bin/env bash
# Install dependencies for ~/.config/mango (excludes waybar and mango).
# Usage: ./install.sh [--dry-run] [--with-canid-dev] [--help]

set -euo pipefail

MANGO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
WITH_CANID_DEV=false

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Install packages required by the Mango config (scripts, rofi, zellij, etc.).
Does not install waybar or mango.

Options:
  --dry-run         Print commands without installing or changing files
  --with-canid-dev  Also install Canid Zellij dev tools (pnpm, lazygit, etc.)
  --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --with-canid-dev) WITH_CANID_DEV=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

run() {
  if $DRY_RUN; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

PKG_MGR=""
PKG_INSTALL=()
PKG_QUERY=()
PKG_NAME=()

detect_pkg_manager() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR=pacman
    PKG_INSTALL=(pacman -S --needed --noconfirm)
    PKG_QUERY=(pacman -Q)
    PKG_NAME=(rofi alacritty zellij flameshot python gettext python-pywal swaybg libnotify pulsemixer dunst pipewire-pulse blueman network-manager-applet slock zenity)
    PKG_OPTIONAL=(pasystray)
    PKG_CANID=(pnpm hasura-cli lazygit lazydocker btop)
    return
  fi
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MGR=apt
    PKG_INSTALL=(apt-get install -y)
    PKG_QUERY=(dpkg -s)
    PKG_NAME=(rofi-wayland alacritty zellij flameshot python3 gettext-base pywal swaybg libnotify-bin pulsemixer dunst pipewire-pulse blueman network-manager-gnome slock zenity)
    PKG_OPTIONAL=()
    PKG_CANID=(pnpm lazygit lazydocker btop)
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    PKG_MGR=dnf
    PKG_INSTALL=(dnf install -y)
    PKG_QUERY=(rpm -q)
    PKG_NAME=(rofi alacritty zellij flameshot python3 gettext python3-pywal swaybg libnotify pulsemixer dunst pipewire-pulseaudio blueman network-manager-applet slock zenity)
    PKG_OPTIONAL=()
    PKG_CANID=(pnpm lazygit lazydocker btop)
    return
  fi
  echo "error: no supported package manager found (pacman, apt-get, or dnf)" >&2
  exit 1
}

is_installed() {
  local pkg="$1"
  case "$PKG_MGR" in
    pacman)
      pacman -Q "$pkg" &>/dev/null
      ;;
    apt)
      dpkg -s "$pkg" &>/dev/null 2>&1
      ;;
    dnf)
      rpm -q "$pkg" &>/dev/null 2>&1
      ;;
  esac
}

install_packages() {
  local -a to_install=()
  local pkg

  for pkg in "$@"; do
    if is_installed "$pkg"; then
      printf 'skip (already installed): %s\n' "$pkg"
    else
      to_install+=("$pkg")
    fi
  done

  if [[ ${#to_install[@]} -eq 0 ]]; then
    return 0
  fi

  printf 'installing: %s\n' "${to_install[*]}"
  run "${PKG_INSTALL[@]}" "${to_install[@]}"
}

install_optional_packages() {
  local pkg
  for pkg in "$@"; do
    if is_installed "$pkg"; then
      printf 'skip (already installed): %s\n' "$pkg"
      continue
    fi
    printf 'installing (optional): %s\n' "$pkg"
    if $DRY_RUN; then
      run "${PKG_INSTALL[@]}" "$pkg"
    elif ! "${PKG_INSTALL[@]}" "$pkg"; then
      warn "optional package failed: $pkg (continuing)"
    fi
  done
}

warn_missing_commands() {
  local cmd
  local -a checks=(rofi alacritty zellij flameshot python3 envsubst wal swaybg notify-send pulsemixer dunstify paplay blueman-applet slock zenity)
  for cmd in "${checks[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      warn "command not found after install: $cmd"
    fi
  done
  if ! command -v python3 >/dev/null 2>&1 && command -v python >/dev/null 2>&1; then
    : # python is fine on Arch
  fi
  if ! command -v pasystray >/dev/null 2>&1; then
    warn "pasystray not found (optional; wallpaper scripts restart it if present)"
  fi
  if ! command -v nm-applet >/dev/null 2>&1; then
    warn "nm-applet not found (check network-manager-applet / network-manager-gnome)"
  fi
}

post_install_setup() {
  printf '\n=== post-install setup ===\n'

  if [[ -d "$MANGO_DIR/scripts" ]]; then
    run chmod +x "$MANGO_DIR"/scripts/*
  fi

  run mkdir -p "$HOME/.local/wallpapers" "$HOME/Pictures/Screenshots"

  local flameshot_xdg="$HOME/.config/flameshot"
  local flameshot_mango="$MANGO_DIR/flameshot"
  if [[ ! -e "$flameshot_xdg" && -d "$flameshot_mango" ]]; then
    printf 'linking %s -> %s\n' "$flameshot_xdg" "$flameshot_mango"
    run ln -s "$flameshot_mango" "$flameshot_xdg"
  elif [[ -e "$flameshot_xdg" ]]; then
    printf 'flameshot config already exists: %s (not overwriting)\n' "$flameshot_xdg"
  fi
}

print_manual_steps() {
  cat <<EOF

=== manual steps (not done by this script) ===

1. Install mango and waybar separately, then log into a Mango session.

2. Deploy this config to ~/.config/mango (or clone this repo there).

3. Add wallpapers under ~/.local/wallpapers/ (jpg/png/webp).

4. Run a wallpaper script once so pywal generates rofi colors:
     bash ~/.config/mango/scripts/wallpaperChangeWayland
   (creates ~/.cache/wal/colors-rofi-dark.rasi used by rofi themes)

5. For Canid (Alt+Shift+X), set project root if not ~/canid:
     export CANID_ROOT=/path/to/canid

6. Reload Mango config after changes: SUPER+r (or mmsg reload if available)

Optional verification:
  bash ~/.config/mango/scripts/volume --get
  bash ~/.config/mango/scripts/rofi_all_apps

EOF
  if $WITH_CANID_DEV; then
    cat <<'EOF'
Canid dev tools (--with-canid-dev):
  hasura may need manual install on Debian/Fedora (https://hasura.io/docs/latest/hasura-cli/install-hasura-cli/)
  pnpm projects: ensure CANID_ROOT/bluefox and CANID_ROOT/backend-api exist
EOF
  fi
}

main() {
  printf 'Mango config dir: %s\n' "$MANGO_DIR"
  detect_pkg_manager
  printf 'Package manager: %s\n' "$PKG_MGR"
  $DRY_RUN && printf 'Mode: dry-run\n'

  if [[ "$PKG_MGR" == apt && $DRY_RUN == false ]]; then
    run apt-get update
  fi

  printf '\n=== core packages ===\n'
  install_packages "${PKG_NAME[@]}"

  if [[ ${#PKG_OPTIONAL[@]} -gt 0 ]]; then
    printf '\n=== optional packages ===\n'
    install_optional_packages "${PKG_OPTIONAL[@]}"
  fi

  if $WITH_CANID_DEV; then
    printf '\n=== Canid dev packages ===\n'
    if [[ "$PKG_MGR" == pacman ]]; then
      install_optional_packages "${PKG_CANID[@]}"
    else
      install_packages "${PKG_CANID[@]}"
      warn "hasura-cli may be unavailable on $PKG_MGR; install manually if needed"
    fi
  fi

  if ! $DRY_RUN; then
    warn_missing_commands
    post_install_setup
  else
    printf '\n[dry-run] skipping post-install file changes\n'
    printf '[dry-run] would: chmod +x %s/scripts/*\n' "$MANGO_DIR"
    printf '[dry-run] would: mkdir -p ~/.local/wallpapers ~/Pictures/Screenshots\n'
    printf '[dry-run] would: symlink ~/.config/flameshot -> %s/flameshot if missing\n' "$MANGO_DIR"
  fi

  print_manual_steps
  printf 'Done.\n'
}

main "$@"
