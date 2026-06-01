#!/usr/bin/env bash
# Install dependencies for ~/.config/mango (excludes mango).
# Usage: ./install.sh [--dry-run] [--with-canid-dev] [--help]

set -euo pipefail

MANGO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
WITH_CANID_DEV=false

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Install packages required by the Mango config (scripts, rofi, zellij, waybar, etc.).
Does not install mango.

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
PKG_HELPER=""
PKG_INSTALL=()
PKG_QUERY=()
PKG_NAME=()
PKG_OPTIONAL=()
PKG_AUR_REQUIRED=()
PKG_AUR=()
PKG_CANID=()

detect_pkg_manager() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR=pacman
    PKG_HELPER=pacman
    PKG_INSTALL=(pacman -S --needed --noconfirm)
    if command -v paru >/dev/null 2>&1; then
      PKG_HELPER=paru
      PKG_INSTALL=(paru -S --needed --noconfirm)
    elif command -v yay >/dev/null 2>&1; then
      PKG_HELPER=yay
      PKG_INSTALL=(yay -S --needed --noconfirm)
    fi
    PKG_QUERY=(pacman -Q)
    PKG_NAME=(
      rofi alacritty zellij waybar python gettext python-pywal awww
      libnotify pulsemixer dunst pipewire pipewire-audio pipewire-pulse
      pipewire-alsa wireplumber pavucontrol blueman bluez bluez-utils rfkill
      networkmanager network-manager-applet zenity xdg-desktop-portal-wlr
      mate-polkit qt5-wayland qt6-wayland qt6ct nwg-look gnome-themes-extra
      noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-jetbrains-mono-nerd
      micro fzf zoxide eza bat fd trash-cli git curl ffmpeg neovim nemo imv mpv
      docker lazygit lazydocker
      brightnessctl playerctl pacman-contrib bash-completion sound-theme-freedesktop
      swaync
    )
    PKG_OPTIONAL=(pasystray)
    PKG_AUR_REQUIRED=(veila-bin)
    PKG_AUR=(google-chrome bluetui dracula-cursors-git)
    PKG_CANID=(pnpm hasura-cli btop)
    return
  fi
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MGR=apt
    PKG_HELPER=apt-get
    PKG_INSTALL=(apt-get install -y)
    PKG_QUERY=(dpkg -s)
    PKG_NAME=(
      rofi-wayland alacritty zellij waybar python3 gettext-base pywal awww
      libnotify-bin pulsemixer dunst pipewire wireplumber pipewire-pulse
      pipewire-alsa pavucontrol blueman bluez bluez-tools rfkill
      network-manager network-manager-gnome zenity xdg-desktop-portal-wlr
      mate-polkit qt5-wayland qt6-wayland qt6ct gnome-themes-extra
      fonts-noto fonts-noto-cjk fonts-noto-color-emoji fonts-jetbrains-mono
      micro fzf zoxide eza bat fd-find trash-cli git curl ffmpeg neovim nemo imv mpv
      brightnessctl playerctl bash-completion sound-theme-freedesktop
    )
    PKG_OPTIONAL=(nwg-look pasystray)
    PKG_CANID=(pnpm lazygit lazydocker btop)
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    PKG_MGR=dnf
    PKG_HELPER=dnf
    PKG_INSTALL=(dnf install -y)
    PKG_QUERY=(rpm -q)
    PKG_NAME=(
      rofi alacritty zellij waybar python3 gettext python3-pywal awww
      libnotify pulsemixer dunst pipewire pipewire-pulseaudio wireplumber
      pipewire-alsa pavucontrol blueman bluez bluez-tools rfkill
      NetworkManager network-manager-applet zenity xdg-desktop-portal-wlr
      mate-polkit qt5-qtwayland qt6-qtwayland qt6ct gnome-themes-extra
      google-noto-sans-fonts google-noto-cjk-fonts google-noto-emoji-fonts
      jetbrains-mono-fonts-all micro fzf zoxide eza bat fd-find trash-cli git curl
      ffmpeg neovim nemo imv mpv brightnessctl playerctl bash-completion
      sound-theme-freedesktop
    )
    PKG_OPTIONAL=(nwg-look pasystray)
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

install_arch_required_aur_packages() {
  if [[ "$PKG_MGR" != pacman || ${#PKG_AUR_REQUIRED[@]} -eq 0 ]]; then
    return 0
  fi

  printf '\n=== required AUR packages ===\n'
  if [[ "$PKG_HELPER" == pacman ]]; then
    warn "paru or yay not found; install required AUR packages manually: ${PKG_AUR_REQUIRED[*]}"
    return 0
  fi

  install_packages "${PKG_AUR_REQUIRED[@]}"
}

install_arch_aur_packages() {
  if [[ "$PKG_MGR" != pacman || ${#PKG_AUR[@]} -eq 0 ]]; then
    return 0
  fi

  printf '\n=== AUR packages ===\n'
  if [[ "$PKG_HELPER" == pacman ]]; then
    warn "paru or yay not found; skipping AUR packages: ${PKG_AUR[*]}"
    return 0
  fi

  install_optional_packages "${PKG_AUR[@]}"
}

warn_missing_commands() {
  local cmd
  local -a checks=(
    rofi alacritty zellij waybar envsubst wal awww notify-send pulsemixer
    dunstify paplay blueman-applet zenity fzf zoxide eza bat brightnessctl
    playerctl nwg-look qt6ct nemo imv mpv bluetoothctl rfkill nm-applet
    pavucontrol fc-cache fd trash git curl ffmpeg nvim micro docker lazygit lazydocker
    veila veilad veila-curtain
  )
  for cmd in "${checks[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      warn "command not found after install: $cmd"
    fi
  done
  if ! command -v python3 >/dev/null 2>&1 && command -v python >/dev/null 2>&1; then
    : # python is fine on Arch
  elif ! command -v python3 >/dev/null 2>&1; then
    warn "command not found after install: python3 (or python on Arch)"
  fi
  if ! command -v pasystray >/dev/null 2>&1; then
    warn "pasystray not found (optional; wallpaper scripts restart it if present)"
  fi
  if ! command -v nm-applet >/dev/null 2>&1; then
    warn "nm-applet not found (check network-manager-applet / network-manager-gnome)"
  fi
  if ! command -v bluetui >/dev/null 2>&1; then
    warn "bluetui not found (optional; used by the Waybar Bluetooth click action)"
  fi
}

link_if_missing() {
  local source="$1"
  local target="$2"
  local label="$3"
  local parent

  parent="$(dirname "$target")"
  run mkdir -p "$parent"

  if [[ ! -e "$target" && ! -L "$target" && -e "$source" ]]; then
    printf 'linking %s -> %s\n' "$target" "$source"
    run ln -s "$source" "$target"
  elif [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    printf '%s already linked: %s -> %s\n' "$label" "$target" "$source"
  elif [[ -e "$target" || -L "$target" ]]; then
    printf '%s already exists: %s (not overwriting)\n' "$label" "$target"
  elif [[ ! -e "$source" ]]; then
    warn "$label source missing: $source"
  fi
}

link_replace() {
  local source="$1"
  local target="$2"
  local label="$3"
  local parent

  parent="$(dirname "$target")"
  run mkdir -p "$parent"

  if [[ ! -e "$source" ]]; then
    warn "$label source missing: $source"
    return 0
  fi

  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    printf '%s already linked: %s -> %s\n' "$label" "$target" "$source"
    return 0
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    printf 'replacing %s: %s -> %s\n' "$label" "$target" "$source"
    run rm -rf "$target"
  else
    printf 'linking %s -> %s\n' "$target" "$source"
  fi

  run ln -s "$source" "$target"
}

setup_qt_environment() {
  local env_dir="$HOME/.config/environment.d"
  local env_file="$env_dir/mango.conf"
  local env_line="QT_QPA_PLATFORMTHEME=qt6ct"

  if [[ -f "$env_file" ]] && grep -Eq '^QT_QPA_PLATFORMTHEME=' "$env_file"; then
    if grep -qx "$env_line" "$env_file"; then
      printf 'Qt platform theme already configured in %s\n' "$env_file"
    else
      warn "QT_QPA_PLATFORMTHEME is already set in $env_file (not overwriting)"
      warn "set it to qt6ct manually if you want qt6ct to control Qt dialogs"
    fi
    return 0
  fi

  if $DRY_RUN; then
    printf '[dry-run] would: append %s to %s\n' "$env_line" "$env_file"
    return 0
  fi

  mkdir -p "$env_dir"
  printf '%s\n' "$env_line" >> "$env_file"
  printf 'configured Qt platform theme in %s\n' "$env_file"
}

check_session_startup() {
  local startup_conf="$MANGO_DIR/modules/startup.conf"

  if [[ ! -f "$startup_conf" ]]; then
    warn "Mango startup file not found: $startup_conf"
    return 0
  fi

  if ! grep -Eq 'mate-polkit|polkit-mate-authentication-agent-1' "$startup_conf"; then
    warn "polkit agent is not listed in $startup_conf"
    warn "add: exec-once=/usr/lib/mate-polkit/polkit-mate-authentication-agent-1"
  fi

  if ! grep -Eq 'xdg-desktop-portal-wlr|xdg-desktop-portal' "$startup_conf"; then
    warn "xdg desktop portal is not listed in $startup_conf"
    warn "add: exec-once=/usr/lib/xdg-desktop-portal-wlr"
  fi
}

post_install_setup() {
  printf '\n=== post-install setup ===\n'

  if [[ -d "$MANGO_DIR/scripts" ]]; then
    run chmod +x "$MANGO_DIR"/scripts/*
  fi

  run mkdir -p "$HOME/.local/wallpapers" "$HOME/Pictures/Screenshots"

  link_replace "$MANGO_DIR/alacritty" "$HOME/.config/alacritty" "alacritty config"
  link_if_missing "$MANGO_DIR/waybar" "$HOME/.config/waybar" "waybar config"
  link_if_missing "$MANGO_DIR/swaync" "$HOME/.config/swaync" "swaync config"
  link_if_missing "$MANGO_DIR/veila" "$HOME/.config/veila" "veila config"
  link_if_missing "$MANGO_DIR/bashrc/.bashrc" "$HOME/.bashrc" "bashrc"
  link_if_missing "$MANGO_DIR/bashrc/.bash_aliases" "$HOME/.bash_aliases" "bash aliases"

  if command -v fc-cache >/dev/null 2>&1; then
    run fc-cache -fv
  else
    warn "fc-cache not found; install fontconfig and run fc-cache -fv after installing fonts"
  fi

  setup_qt_environment
  check_session_startup
}

print_manual_steps() {
  cat <<EOF

=== manual steps (not done by this script) ===

1. Install mango separately, then log into a Mango session.

2. Deploy this config to ~/.config/mango (or clone this repo there).

3. On Debian/Ubuntu or Fedora, install Veila from the official release package:
     https://naurissteins.com/veila/docs/installation/debian-ubuntu
     https://naurissteins.com/veila/docs/installation/fedora
   On Arch/Cachy, this installer uses the veila-bin AUR package when paru/yay is available.

4. Restart the shell or source the linked bash config:
     source ~/.bashrc

5. Add wallpapers under ~/.local/wallpapers/ (jpg/png/webp).

6. Run a wallpaper script once so pywal generates rofi and Veila colors:
     bash ~/.config/mango/scripts/wallpaperChangeWayland
   (creates ~/.cache/wal/colors-rofi-dark.rasi and ~/.cache/wal/veila.toml)

7. Open nwg-look and choose a dark GTK theme such as Adwaita-dark or Dracula.
   Set the color scheme preference to dark.

8. Open qt6ct and choose darker standard dialogs/theme settings.
   QT_QPA_PLATFORMTHEME=qt6ct is written to ~/.config/environment.d/mango.conf
   when that variable is not already configured there.

9. If you want the Waybar Bluetooth click to use bluetui, set:
     "on-click": "exec alacritty --title=bluetui -e bluetui"
   in ~/.config/waybar/modules/bluetooth.jsonc

10. The Mango session starts Veila automatically:
      veilad
      veila idle --lock-after=120 --lock-before-sleep
    Veila locks after 120s idle and suspends 180s after lock readiness
    (about 300s after idle begins). It uses ~/.config/veila/config.toml
    and the current pywal wallpaper from ~/.cache/wal/veila.toml.

11. For Canid (Alt+Shift+X), set project root if not ~/canid:
     export CANID_ROOT=/path/to/canid

12. Reload Mango config after changes: SUPER+r (or mmsg reload if available)
    Restart Waybar if needed:
      bash ~/.config/mango/scripts/reloadWaybar --with-colors

Optional verification:
  bash ~/.config/mango/scripts/volume --get
  bash ~/.config/mango/scripts/rofi_all_apps
  veila check-config --config ~/.config/mango/veila/config.toml
  veila lock --wait-ready
  bash ~/.config/mango/scripts/lockWayland
  brightnessctl --list
  playerctl --version
  bluetui --help

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
  if [[ -n "$PKG_HELPER" && "$PKG_HELPER" != "$PKG_MGR" ]]; then
    printf 'Install helper: %s\n' "$PKG_HELPER"
  fi
  $DRY_RUN && printf 'Mode: dry-run\n'

  if [[ "$PKG_MGR" == apt && $DRY_RUN == false ]]; then
    run apt-get update
  fi

  printf '\n=== core packages ===\n'
  install_packages "${PKG_NAME[@]}"

  install_arch_required_aur_packages

  if [[ ${#PKG_OPTIONAL[@]} -gt 0 ]]; then
    printf '\n=== optional packages ===\n'
    install_optional_packages "${PKG_OPTIONAL[@]}"
  fi

  install_arch_aur_packages

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
    printf '[dry-run] would: replace ~/.config/alacritty with symlink -> %s/alacritty\n' "$MANGO_DIR"
    printf '[dry-run] would: symlink ~/.config/waybar -> %s/waybar if missing\n' "$MANGO_DIR"
    printf '[dry-run] would: symlink ~/.config/swaync -> %s/swaync if missing\n' "$MANGO_DIR"
    printf '[dry-run] would: symlink ~/.config/veila -> %s/veila if missing\n' "$MANGO_DIR"
    printf '[dry-run] would: symlink ~/.bashrc -> %s/bashrc/.bashrc if missing\n' "$MANGO_DIR"
    printf '[dry-run] would: symlink ~/.bash_aliases -> %s/bashrc/.bash_aliases if missing\n' "$MANGO_DIR"
    printf '[dry-run] would: run fc-cache -fv if fc-cache is available\n'
    setup_qt_environment
    check_session_startup
  fi

  print_manual_steps
  printf 'Done.\n'
}

main "$@"
