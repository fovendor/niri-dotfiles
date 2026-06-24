# system-config

Переносимый снимок этой NixOS-системы: системная декларация, локальные костыли, пользовательские конфиги и манифесты приложений.

## Что здесь лежит

- `system/etc/nixos/` - текущий `/etc/nixos`, включая `dsdt-x677-patched.aml` для клавиатуры Maibenben/Tongfang.
- `home/` - выбранные dotfiles и текстовые настройки из `~/.config` без cookies, cache, логов и секретов.
- `external/alien-sperm/flydigi-vader5/` - локальный модуль, который импортируется из NixOS-конфига.
- `manifests/` - расширения VS Code, dconf, flatpak remotes/apps и контрольный снимок пользовательского `nix profile`.
- `scripts/` - операции снимка, применения и проверки расхождений.

## Обычный цикл

После ручных изменений в системе:

```bash
~/git/system-config/scripts/snapshot.sh
git -C ~/git/system-config diff
git -C ~/git/system-config add .
git -C ~/git/system-config commit -m "Update system snapshot"
```

Обновление системы через Nix и сохранение результата:

```bash
~/git/system-config/scripts/update-system.sh
```

Проверка, не разъехалась ли живая система с репозиторием:

```bash
~/git/system-config/scripts/check-drift.sh
```

## Восстановление на новой NixOS

1. Забрать этот репозиторий в `~/git/system-config`.
2. Убедиться, что пользователь называется `fovendor`, либо поправить абсолютные пути в `system/etc/nixos/configuration.nix`.
3. Применить конфиги:

```bash
~/git/system-config/scripts/apply.sh --rebuild
```

Скрипт делает backup существующих файлов в `~/.local/state/system-config-backups/`.

## Про обновления VS Code и Mattermost

Оба приложения установлены через NixOS, поэтому их внутренние update-проверки отключены в пользовательских настройках:

- VS Code: `"update.mode": "none"`.
- Mattermost: `"autoCheckForUpdates": false`.

Версии должны меняться через `sudo nixos-rebuild switch` и изменение Nix-конфига, а не через updater самого приложения.

## Источник истины для пакетов

Пакеты должны добавляться в `environment.systemPackages` внутри `system/etc/nixos/configuration.nix`.
Пользовательский `nix profile` намеренно держится пустым, чтобы не было второго недекларативного источника программ и версий.
