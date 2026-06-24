#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
home_dir="${HOME:?}"
backup_root="$home_dir/.local/state/system-config-backups/$(date +%Y%m%d-%H%M%S)"
do_rebuild=0

usage() {
  cat <<'EOF'
Usage: scripts/apply.sh [--rebuild]

Restores system and user configuration from this repository.
Existing files are backed up under ~/.local/state/system-config-backups.

Options:
  --rebuild   Run sudo nixos-rebuild switch after copying /etc/nixos.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --rebuild) do_rebuild=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

backup_path() {
  local path="$1"
  local rel="${path#$home_dir/}"

  if [[ -e "$path" || -L "$path" ]]; then
    mkdir -p "$backup_root/$(dirname "$rel")"
    rsync -a "$path" "$backup_root/$rel"
  fi
}

restore_file() {
  local src="$1"
  local dst="$2"

  if [[ -f "$repo_root/$src" ]]; then
    backup_path "$dst"
    install -D -m 0644 "$repo_root/$src" "$dst"
  fi
}

restore_dir() {
  local src="$1"
  local dst="$2"

  if [[ -d "$repo_root/$src" ]]; then
    backup_path "$dst"
    mkdir -p "$dst"
    rsync -a --delete "$repo_root/$src"/ "$dst"/
  fi
}

mkdir -p "$backup_root"

sudo mkdir -p /etc/nixos
sudo rsync -a "/etc/nixos/" "$backup_root/etc-nixos/" 2>/dev/null || true
sudo rsync -a --delete "$repo_root/system/etc/nixos/" /etc/nixos/

restore_file "home/dotfiles/.bashrc" "$home_dir/.bashrc"
restore_file "home/dotfiles/.gitconfig" "$home_dir/.gitconfig"
restore_file "home/dotfiles/.Xresources" "$home_dir/.Xresources"
restore_file "home/dotfiles/.nvidia-settings-rc" "$home_dir/.nvidia-settings-rc"

for dir in \
  niri ghostty kitty alacritty btop htop yazi broot superfile \
  gtk-3.0 gtk-4.0 fontconfig environment.d autostart mpv \
  qBittorrent godot systemd
do
  restore_dir "home/.config/$dir" "$home_dir/.config/$dir"
done

restore_dir "home/.config/Code/User" "$home_dir/.config/Code/User"
restore_dir "home/.config/Mattermost" "$home_dir/.config/Mattermost"
restore_file "home/.config/mimeapps.list" "$home_dir/.config/mimeapps.list"
restore_file "home/.config/user-dirs.dirs" "$home_dir/.config/user-dirs.dirs"
restore_file "home/.config/user-dirs.locale" "$home_dir/.config/user-dirs.locale"
restore_dir "home/.local/share/applications" "$home_dir/.local/share/applications"
restore_dir "home/.local/share/nautilus/scripts" "$home_dir/.local/share/nautilus/scripts"
restore_dir "external/alien-sperm/flydigi-vader5" "$home_dir/.local/share/alien-sperm/flydigi-vader5"

if [[ -s "$repo_root/manifests/vscode-extensions.txt" ]] && command -v code >/dev/null 2>&1; then
  while IFS= read -r extension; do
    [[ -n "$extension" ]] && code --install-extension "$extension" --force >/dev/null
  done < "$repo_root/manifests/vscode-extensions.txt"
fi

if [[ -s "$repo_root/manifests/dconf.ini" ]] && command -v dconf >/dev/null 2>&1; then
  dconf load / < "$repo_root/manifests/dconf.ini"
fi

if (( do_rebuild )); then
  sudo nixos-rebuild switch
else
  printf 'Copied configs. Run sudo nixos-rebuild switch when ready.\n'
fi

printf 'Backups: %s\n' "$backup_root"

