#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
home_dir="${HOME:?}"

copy_file() {
  local src="$1"
  local dst="$2"

  if [[ -f "$src" ]]; then
    install -D -m 0644 "$src" "$repo_root/$dst"
  fi
}

copy_dir() {
  local src="$1"
  local dst="$2"
  shift 2

  if [[ -d "$src" ]]; then
    mkdir -p "$repo_root/$dst"
    rsync -a --delete "$@" "$src"/ "$repo_root/$dst"/
  fi
}

write_command_output() {
  local dst="$1"
  shift

  mkdir -p "$(dirname "$repo_root/$dst")"
  "$@" > "$repo_root/$dst" 2>/dev/null || true
}

mkdir -p "$repo_root"/{system/etc/nixos,home/dotfiles,home/.config,home/.local/share,manifests,external}

sudo rsync -a --delete \
  --chown="$(id -u):$(id -g)" \
  --exclude='configuration.nix.bak-*' \
  --exclude='configuration.nix.~*~' \
  /etc/nixos/ "$repo_root/system/etc/nixos"/

copy_file "$home_dir/.bashrc" "home/dotfiles/.bashrc"
copy_file "$home_dir/.gitconfig" "home/dotfiles/.gitconfig"
copy_file "$home_dir/.Xresources" "home/dotfiles/.Xresources"
copy_file "$home_dir/.nvidia-settings-rc" "home/dotfiles/.nvidia-settings-rc"

for dir in \
  niri ghostty kitty alacritty btop htop yazi broot superfile \
  gtk-3.0 gtk-4.0 fontconfig environment.d autostart mpv \
  qBittorrent godot systemd
do
  copy_dir "$home_dir/.config/$dir" "home/.config/$dir" \
    --exclude='*.lock' \
    --exclude='lockfile' \
    --exclude='*.log' \
    --exclude='cache/' \
    --exclude='Cache/' \
    --exclude='GPUCache/' \
    --exclude='CachedData/'
done

mkdir -p "$repo_root/home/.config/Code/User"
copy_file "$home_dir/.config/Code/User/settings.json" "home/.config/Code/User/settings.json"
copy_file "$home_dir/.config/Code/User/keybindings.json" "home/.config/Code/User/keybindings.json"
copy_dir "$home_dir/.config/Code/User/snippets" "home/.config/Code/User/snippets"

mkdir -p "$repo_root/home/.config/Mattermost"
copy_file "$home_dir/.config/Mattermost/config.json" "home/.config/Mattermost/config.json"
copy_file "$home_dir/.config/Mattermost/bounds-info.json" "home/.config/Mattermost/bounds-info.json"
copy_file "$home_dir/.config/Mattermost/app-state.json" "home/.config/Mattermost/app-state.json"

copy_file "$home_dir/.config/mimeapps.list" "home/.config/mimeapps.list"
copy_file "$home_dir/.config/user-dirs.dirs" "home/.config/user-dirs.dirs"
copy_file "$home_dir/.config/user-dirs.locale" "home/.config/user-dirs.locale"
copy_dir "$home_dir/.local/share/applications" "home/.local/share/applications"
copy_dir "$home_dir/.local/share/nautilus/scripts" "home/.local/share/nautilus/scripts"

copy_dir "$home_dir/.local/share/alien-sperm/flydigi-vader5" "external/alien-sperm/flydigi-vader5" \
  --exclude='.git/' \
  --exclude='build/' \
  --exclude='result' \
  --exclude='*.o' \
  --exclude='*.so'

{
  printf 'snapshot_time=%s\n' "$(date --iso-8601=seconds)"
  printf 'user=%s\n' "$(id -un)"
  printf 'host=%s\n' "$(hostname)"
  printf 'kernel=%s\n' "$(uname -srmo)"
  printf '\n[os-release]\n'
  sed -n '1,120p' /etc/os-release
} > "$repo_root/manifests/host-info.txt"

write_command_output "manifests/flatpak-apps.tsv" flatpak list --app --columns=application,origin,branch,installation
write_command_output "manifests/flatpak-remotes.tsv" flatpak remotes --columns=name,url
write_command_output "manifests/nix-profile.txt" nix profile list
write_command_output "manifests/dconf.ini" dconf dump /

if command -v code >/dev/null 2>&1; then
  write_command_output "manifests/vscode-extensions.txt" code --list-extensions
fi
if command -v codium >/dev/null 2>&1; then
  write_command_output "manifests/codium-extensions.txt" codium --list-extensions
fi

git -C "$repo_root" status --short
