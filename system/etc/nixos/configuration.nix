# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

let
  noctaliaFlake = builtins.getFlake "github:noctalia-dev/noctalia-shell/0fcaa49875bf0c994bb5c604320454ef72e6ba8b";
  mattermostDesktopPkg = (builtins.getFlake "github:NixOS/nixpkgs/13043924aaa7375ce482ebe2494338e058282925").legacyPackages.${pkgs.stdenv.hostPlatform.system}.mattermost-desktop;
  niriSessionWithWayland = pkgs.writeShellScript "niri-session-with-wayland" ''
    export NIXOS_OZONE_WL=1
    exec niri-session
  '';
  codeWaylandWrapper = lib.hiPrio (pkgs.writeShellScriptBin "code" ''
    export NIXOS_OZONE_WL="''${NIXOS_OZONE_WL:-1}"
    exec ${pkgs.vscode}/bin/code "$@"
  '');
  nautilusImagesToPdfScript = pkgs.writeShellScriptBin "nautilus-create-images-pdf" ''
    set -u

    selected=()
    if [ -n "''${NAUTILUS_SCRIPT_SELECTED_FILE_PATHS:-}" ]; then
      while IFS= read -r path; do
        [ -n "$path" ] && selected+=("$path")
      done <<< "$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS"
    else
      for path in "$@"; do
        [ -n "$path" ] && selected+=("$path")
      done
    fi

    images=()
    for path in "''${selected[@]}"; do
      [ -f "$path" ] || continue
      case "''${path,,}" in
        *.avif|*.bmp|*.gif|*.jp2|*.jpe|*.jpeg|*.jpg|*.jxl|*.png|*.tif|*.tiff|*.webp)
          images+=("$path")
          ;;
      esac
    done

    error_dir="''${PWD:-$HOME}"
    if [ "''${#images[@]}" -gt 0 ]; then
      error_dir="$(${pkgs.coreutils}/bin/dirname "''${images[0]}")"
    fi

    unique_path() {
      local dir="$1"
      local filename="$2"
      local root="''${filename%.*}"
      local ext=".''${filename##*.}"
      local candidate="$dir/$filename"
      local counter=2
      while [ -e "$candidate" ]; do
        candidate="$dir/$root-$counter$ext"
        counter=$((counter + 1))
      done
      printf '%s\n' "$candidate"
    }

    write_error() {
      local error_path
      error_path="$(unique_path "$error_dir" "image-to-pdf-error.txt")"
      {
        printf '%s\n\n' "$1"
        shift
        printf '%s\n' "$@"
      } > "$error_path"
      ${pkgs.glib}/bin/gio open "$error_path" >/dev/null 2>&1 || true
    }

    if [ "''${#images[@]}" -eq 0 ]; then
      write_error "No selected image files." "Select one or more images and run the script again."
      exit 1
    fi

    sorted=()
    while IFS= read -r -d "" path; do
      sorted+=("$path")
    done < <(printf '%s\0' "''${images[@]}" | ${pkgs.coreutils}/bin/sort -z -V)

    output_dir="$(${pkgs.coreutils}/bin/dirname "''${sorted[0]}")"
    if [ "''${#sorted[@]}" -eq 1 ]; then
      base="$(${pkgs.coreutils}/bin/basename "''${sorted[0]}")"
      output_name="''${base%.*}.pdf"
    else
      output_name="selected-images.pdf"
    fi
    output_path="$(unique_path "$output_dir" "$output_name")"

    if ${pkgs.img2pdf}/bin/img2pdf "''${sorted[@]}" -o "$output_path" >"$output_path.log" 2>&1; then
      rm -f "$output_path.log"
      ${pkgs.glib}/bin/gio open "$output_path" >/dev/null 2>&1 || true
    else
      log="$(cat "$output_path.log" 2>/dev/null || true)"
      rm -f "$output_path.log"
      write_error "img2pdf failed." "$log"
      exit 1
    fi
  '';
  nautilusNativeExtensions = pkgs.stdenv.mkDerivation {
    pname = "nautilus-native-extensions";
    version = "local-2026-06-15";
    dontUnpack = true;
    nativeBuildInputs = with pkgs; [
      pkg-config
    ];
    buildInputs = with pkgs; [
      glib
      nautilus.dev
    ];
    buildPhase = ''
      runHook preBuild

      cat > ghostty-nautilus.c <<'EOF'
      #include <nautilus-extension.h>
      #include <gio/gio.h>
      #include <glib.h>
      #include <glib-object.h>

      #define GHOSTTY_BIN "${pkgs.ghostty}/bin/ghostty"

      typedef struct {
        GObject parent_instance;
      } GhosttyMenuProvider;

      typedef struct {
        GObjectClass parent_class;
      } GhosttyMenuProviderClass;

      static GType provider_types[1];

      static void ghostty_menu_provider_menu_provider_iface_init (NautilusMenuProviderInterface *iface);

      G_DEFINE_DYNAMIC_TYPE_EXTENDED (
        GhosttyMenuProvider,
        ghostty_menu_provider,
        G_TYPE_OBJECT,
        0,
        G_IMPLEMENT_INTERFACE_DYNAMIC (
          NAUTILUS_TYPE_MENU_PROVIDER,
          ghostty_menu_provider_menu_provider_iface_init))

      static gboolean
      path_is_known (GPtrArray *paths, const char *path)
      {
        for (guint i = 0; i < paths->len; i++) {
          if (g_strcmp0 (g_ptr_array_index (paths, i), path) == 0) {
            return TRUE;
          }
        }
        return FALSE;
      }

      static void
      add_path_for_file (GPtrArray *paths, NautilusFileInfo *file)
      {
        GFile *location = NULL;
        char *path = NULL;

        if (nautilus_file_info_is_directory (file)) {
          location = nautilus_file_info_get_location (file);
        } else {
          location = nautilus_file_info_get_parent_location (file);
        }

        if (location == NULL) {
          return;
        }

        path = g_file_get_path (location);
        g_object_unref (location);

        if (path == NULL) {
          return;
        }

        if (path_is_known (paths, path)) {
          g_free (path);
        } else {
          g_ptr_array_add (paths, path);
        }
      }

      static void
      open_ghostty_activated (NautilusMenuItem *item, gpointer user_data)
      {
        GStrv paths = g_object_get_data (G_OBJECT (item), "ghostty-paths");

        if (paths == NULL) {
          return;
        }

        for (guint i = 0; paths[i] != NULL; i++) {
          g_autofree char *working_directory_arg = NULL;
          GError *error = NULL;
          const char *argv[4];

          working_directory_arg = g_strdup_printf ("--working-directory=%s", paths[i]);
          argv[0] = GHOSTTY_BIN;
          argv[1] = working_directory_arg;
          argv[2] = "--gtk-single-instance=false";
          argv[3] = NULL;

          if (!g_spawn_async (
                NULL,
                (char **) argv,
                NULL,
                G_SPAWN_DEFAULT,
                NULL,
                NULL,
                NULL,
                &error)) {
            g_warning ("Failed to launch Ghostty: %s", error->message);
            g_clear_error (&error);
          }
        }
      }

      static GList *
      make_menu_items_for_paths (GPtrArray *paths)
      {
        NautilusMenuItem *item;

        if (paths->len == 0) {
          g_ptr_array_free (paths, TRUE);
          return NULL;
        }

        g_ptr_array_add (paths, NULL);

        item = nautilus_menu_item_new (
          "GhosttyNative::open_here",
          "Открыть в Ghostty",
          "Открыть выбранное место в Ghostty",
          "com.mitchellh.ghostty");
        g_object_set_data_full (
          G_OBJECT (item),
          "ghostty-paths",
          g_ptr_array_free (paths, FALSE),
          (GDestroyNotify) g_strfreev);
        g_signal_connect (item, "activate", G_CALLBACK (open_ghostty_activated), NULL);

        return g_list_append (NULL, item);
      }

      static GList *
      ghostty_menu_provider_get_file_items (NautilusMenuProvider *provider, GList *files)
      {
        GPtrArray *paths = g_ptr_array_new_with_free_func (g_free);

        for (GList *node = files; node != NULL; node = node->next) {
          add_path_for_file (paths, NAUTILUS_FILE_INFO (node->data));
        }

        return make_menu_items_for_paths (paths);
      }

      static GList *
      ghostty_menu_provider_get_background_items (NautilusMenuProvider *provider,
                                                  NautilusFileInfo *current_folder)
      {
        GPtrArray *paths = g_ptr_array_new_with_free_func (g_free);
        GFile *location = nautilus_file_info_get_location (current_folder);

        if (location != NULL) {
          char *path = g_file_get_path (location);
          g_object_unref (location);
          if (path != NULL) {
            g_ptr_array_add (paths, path);
          }
        }

        return make_menu_items_for_paths (paths);
      }

      static void
      ghostty_menu_provider_menu_provider_iface_init (NautilusMenuProviderInterface *iface)
      {
        iface->get_file_items = ghostty_menu_provider_get_file_items;
        iface->get_background_items = ghostty_menu_provider_get_background_items;
      }

      static void
      ghostty_menu_provider_class_init (GhosttyMenuProviderClass *klass)
      {
      }

      static void
      ghostty_menu_provider_class_finalize (GhosttyMenuProviderClass *klass)
      {
      }

      static void
      ghostty_menu_provider_init (GhosttyMenuProvider *provider)
      {
      }

      void
      nautilus_module_initialize (GTypeModule *module)
      {
        ghostty_menu_provider_register_type (module);
        provider_types[0] = ghostty_menu_provider_get_type ();
      }

      void
      nautilus_module_shutdown (void)
      {
      }

      void
      nautilus_module_list_types (const GType **types, int *num_types)
      {
        *types = provider_types;
        *num_types = 1;
      }
      EOF

      cc -fPIC -shared ghostty-nautilus.c -o libghostty-nautilus.so \
        $(pkg-config --cflags --libs libnautilus-extension-4)

      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall

      install -Dm755 libghostty-nautilus.so \
        "$out/lib/nautilus/extensions-4/libghostty-nautilus.so"

      for extension in ${pkgs.nautilus}/lib/nautilus/extensions-4/*.so; do
        ln -s "$extension" "$out/lib/nautilus/extensions-4/$(basename "$extension")"
      done

      runHook postInstall
    '';
  };
  x677AcpiOverride = pkgs.runCommand "x677-acpi-override" {
    nativeBuildInputs = [ pkgs.cpio ];
  } ''
    mkdir -p kernel/firmware/acpi
    cp ${./dsdt-x677-patched.aml} kernel/firmware/acpi/dsdt.aml
    find kernel | cpio -H newc --create > "$out"
  '';
  nautilusAdmin = pkgs.stdenvNoCC.mkDerivation {
    pname = "nautilus-admin";
    version = "local-2026-04-12";
    dontUnpack = true;
    installPhase = ''
      install -Dm644 ${pkgs.writeText "nautilus_admin.py" ''
        from urllib.parse import quote
        import os
        import subprocess

        from gi import get_required_version
        from gi.repository import GObject

        if get_required_version("Nautilus") is None:
            raise RuntimeError("Nautilus API is not available")
        from gi.repository import Nautilus as FileManager

        NAUTILUS_BIN = "${pkgs.nautilus}/bin/nautilus"
        GIO_BIN = "${pkgs.glib}/bin/gio"


        def _admin_uri(file_):
            location = file_.get_location()
            if location is None:
                return None
            path = location.get_path()
            if not path:
                return None
            return "admin://" + quote(path)


        class NautilusAdminExtension(GObject.GObject, FileManager.MenuProvider):
            def _open_folder_admin(self, _menu, file_):
                admin_uri = _admin_uri(file_)
                if admin_uri:
                    subprocess.Popen([NAUTILUS_BIN, admin_uri])

            def _open_file_admin(self, _menu, file_):
                admin_uri = _admin_uri(file_)
                if admin_uri:
                    subprocess.Popen([GIO_BIN, "open", admin_uri])

            def get_file_items(self, *args):
                files = args[-1]
                if os.geteuid() == 0 or len(files) != 1:
                    return []

                file_ = files[0]
                if file_.get_uri_scheme() != "file":
                    return []

                if file_.is_directory():
                    item = FileManager.MenuItem(
                        name="NautilusAdmin::open_folder_admin",
                        label="Open as Administrator",
                        tip="Open this folder with administrator privileges",
                    )
                    item.connect("activate", self._open_folder_admin, file_)
                    return [item]

                item = FileManager.MenuItem(
                    name="NautilusAdmin::open_file_admin",
                    label="Edit as Administrator",
                    tip="Open this file with administrator privileges",
                )
                item.connect("activate", self._open_file_admin, file_)
                return [item]

            def get_background_items(self, *args):
                file_ = args[-1]
                if os.geteuid() == 0 or file_.get_uri_scheme() != "file" or not file_.is_directory():
                    return []

                item = FileManager.MenuItem(
                    name="NautilusAdmin::open_background_admin",
                    label="Open as Administrator",
                    tip="Open this folder with administrator privileges",
                )
                item.connect("activate", self._open_folder_admin, file_)
                return [item]
      ''} $out/${pkgs.python3.sitePackages}/nautilus_admin.py
      install -Dm644 $out/${pkgs.python3.sitePackages}/nautilus_admin.py \
        $out/share/nautilus-python/extensions/nautilus_admin.py
    '';
  };
  unstablePkgs = import (builtins.fetchTarball "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz") {
    localSystem = { system = pkgs.stdenv.hostPlatform.system; };
    config = pkgs.config;
  };
  homeManagerModule = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/release-25.11.tar.gz";

  nautilusEmblems = pkgs.stdenvNoCC.mkDerivation {
    pname = "nautilus-emblems";
    version = "local-2026-04-12";
    dontUnpack = true;
    installPhase = ''
      install -Dm644 ${pkgs.writeText "nautilus_emblems.py" ''
        import subprocess

        from gi import get_required_version
        from gi.repository import GObject

        if get_required_version("Nautilus") is None:
            raise RuntimeError("Nautilus API is not available")
        from gi.repository import Nautilus as FileManager

        GIO_BIN = "${pkgs.glib}/bin/gio"

        EMBLEMS = [
            "emblem-default",
            "emblem-documents",
            "emblem-downloads",
            "emblem-favorite",
            "emblem-important",
            "emblem-mail",
            "emblem-photos",
            "emblem-readonly",
            "emblem-shared",
            "emblem-symbolic-link",
            "emblem-synchronized",
            "emblem-system",
            "emblem-unreadable",
        ]


        def _file_paths(files):
            paths = []
            for file_ in files:
                if file_.get_uri_scheme() != "file":
                    continue
                location = file_.get_location()
                if location is None:
                    continue
                path = location.get_path()
                if path:
                    paths.append(path)
            return paths


        def _read_emblems(path):
            proc = subprocess.run(
                [GIO_BIN, "info", "-a", "metadata::emblems", path],
                check=False,
                capture_output=True,
                text=True,
            )
            if proc.returncode != 0:
                return []
            for line in proc.stdout.splitlines():
                line = line.strip()
                if not line.startswith("metadata::emblems:"):
                    continue
                payload = line.split(":", 1)[1].strip()
                if payload.startswith("[") and payload.endswith("]"):
                    payload = payload[1:-1]
                return [item.strip() for item in payload.split(",") if item.strip()]
            return []


        def _write_emblems(path, emblems):
            if emblems:
                subprocess.run(
                    [GIO_BIN, "set", "-t", "stringv", path, "metadata::emblems", *emblems],
                    check=False,
                )
            else:
                subprocess.run(
                    [GIO_BIN, "set", "-t", "unset", path, "metadata::emblems"],
                    check=False,
                )


        class NautilusEmblemsExtension(GObject.GObject, FileManager.MenuProvider):
            def _add_emblem(self, _menu, files, emblem):
                for path in _file_paths(files):
                    current = _read_emblems(path)
                    if emblem not in current:
                        current.append(emblem)
                        _write_emblems(path, current)

            def _clear_emblems(self, _menu, files):
                for path in _file_paths(files):
                    _write_emblems(path, [])

            def get_file_items(self, *args):
                files = args[-1]
                if not files:
                    return []

                paths = _file_paths(files)
                if not paths:
                    return []

                menu_root = FileManager.MenuItem(
                    name="NautilusEmblems::root",
                    label="Emblems",
                    tip="Set or clear file emblems",
                )
                submenu = FileManager.Menu()
                menu_root.set_submenu(submenu)

                for emblem in EMBLEMS:
                    label = emblem.replace("emblem-", "").replace("-", " ").title()
                    emblem_item = FileManager.MenuItem(
                        name=f"NautilusEmblems::{emblem}",
                        label=label,
                        tip=f"Add {label} emblem",
                    )
                    emblem_item.connect("activate", self._add_emblem, files, emblem)
                    submenu.append_item(emblem_item)

                clear_item = FileManager.MenuItem(
                    name="NautilusEmblems::clear",
                    label="Clear Emblems",
                    tip="Remove all emblems",
                )
                clear_item.connect("activate", self._clear_emblems, files)
                submenu.append_item(clear_item)
                return [menu_root]
      ''} $out/${pkgs.python3.sitePackages}/nautilus_emblems.py
      install -Dm644 $out/${pkgs.python3.sitePackages}/nautilus_emblems.py \
        $out/share/nautilus-python/extensions/nautilus_emblems.py
    '';
  };
  nautilusImagesToPdf = pkgs.stdenvNoCC.mkDerivation {
    pname = "nautilus-images-to-pdf";
    version = "local-2026-06-15";
    dontUnpack = true;
    installPhase = ''
      install -Dm644 ${pkgs.writeText "nautilus_images_to_pdf.py" ''
        import os
        import re
        import subprocess

        from gi import get_required_version
        from gi.repository import GObject

        if get_required_version("Nautilus") is None:
            raise RuntimeError("Nautilus API is not available")
        from gi.repository import Nautilus as FileManager

        GIO_BIN = "${pkgs.glib}/bin/gio"
        IMG2PDF_BIN = "${pkgs.img2pdf}/bin/img2pdf"
        IMAGE_EXTENSIONS = {
            ".avif",
            ".bmp",
            ".gif",
            ".jp2",
            ".jpe",
            ".jpeg",
            ".jpg",
            ".jxl",
            ".png",
            ".tif",
            ".tiff",
            ".webp",
        }


        def _path_for_file(file_):
            if file_.get_uri_scheme() != "file":
                return None
            location = file_.get_location()
            if location is None:
                return None
            path = location.get_path()
            if not path or not os.path.isfile(path):
                return None
            return path


        def _is_image(path):
            return os.path.splitext(path)[1].lower() in IMAGE_EXTENSIONS


        def _selected_image_paths(files):
            paths = []
            for file_ in files:
                path = _path_for_file(file_)
                if path is None or not _is_image(path):
                    return []
                paths.append(path)
            return paths


        def _natural_key(path):
            name = os.path.basename(path)
            return [
                int(part) if part.isdigit() else part.casefold()
                for part in re.split(r"(\d+)", name)
            ]


        def _unique_path(directory, filename):
            root, ext = os.path.splitext(filename)
            candidate = os.path.join(directory, filename)
            counter = 2
            while os.path.exists(candidate):
                candidate = os.path.join(directory, f"{root}-{counter}{ext}")
                counter += 1
            return candidate


        def _output_path(paths):
            directory = os.path.dirname(paths[0])
            if len(paths) == 1:
                filename = os.path.splitext(os.path.basename(paths[0]))[0] + ".pdf"
            else:
                filename = "selected-images.pdf"
            return _unique_path(directory, filename)


        def _open(path):
            subprocess.Popen([GIO_BIN, "open", path])


        def _write_error(directory, stdout, stderr):
            error_path = _unique_path(directory, "image-to-pdf-error.txt")
            with open(error_path, "w", encoding="utf-8") as handle:
                handle.write("img2pdf failed\n\n")
                if stderr:
                    handle.write("stderr:\n")
                    handle.write(stderr)
                    handle.write("\n")
                if stdout:
                    handle.write("stdout:\n")
                    handle.write(stdout)
                    handle.write("\n")
            _open(error_path)


        class NautilusImagesToPdfExtension(GObject.GObject, FileManager.MenuProvider):
            def _create_pdf(self, _menu, files):
                paths = sorted(_selected_image_paths(files), key=_natural_key)
                if not paths:
                    return

                output_path = _output_path(paths)
                proc = subprocess.run(
                    [IMG2PDF_BIN, *paths, "-o", output_path],
                    check=False,
                    capture_output=True,
                    text=True,
                )

                if proc.returncode == 0:
                    _open(output_path)
                else:
                    _write_error(os.path.dirname(paths[0]), proc.stdout, proc.stderr)

            def get_file_items(self, *args):
                files = args[-1]
                paths = _selected_image_paths(files)
                if not paths:
                    return []

                item = FileManager.MenuItem(
                    name="NautilusImagesToPdf::create_pdf",
                    label="Создать PDF из картинок",
                    tip="Create a PDF from the selected images",
                )
                item.connect("activate", self._create_pdf, files)
                return [item]
      ''} $out/${pkgs.python3.sitePackages}/nautilus_images_to_pdf.py
      install -Dm644 $out/${pkgs.python3.sitePackages}/nautilus_images_to_pdf.py \
        $out/share/nautilus-python/extensions/nautilus_images_to_pdf.py
    '';
  };
in

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      noctaliaFlake.nixosModules.default
      (homeManagerModule + "/nixos")
      /home/fovendor/.local/share/alien-sperm/flydigi-vader5/nixos/vader5d-module.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Для этой линейки ноутбуков (Maibenben/Tongfang) встроенная клавиатура
  # может не инициализироваться из-за особенностей i8042/ACPI.
  # Используем более свежее ядро, где аппаратные исправления появляются раньше.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = [
    # Отключаем мультиплексор PS/2, который часто мешает инициализации клавиатуры.
    "i8042.nomux=1"
    # Игнорируем ошибочные PnP-описания устройства от BIOS/ACPI.
    "i8042.nopnp=1"
    # Отключаем loopback-проверку контроллера, которая ломается на ряде прошивок.
    "i8042.noloop=1"
    # Принудительно сбрасываем контроллер i8042 при старте системы.
    "i8042.reset=1"
    # Упрощённый режим клавиатуры: меньше управляющих команд к контроллеру,
    # иногда это единственный способ обойти BIOS-баги на Tongfang-платформах.
    "i8042.dumbkbd=1"
    # Игнорируем ложные таймауты контроллера i8042 от проблемной прошивки.
    "i8042.notimeout=1"
    # Явно сбрасываем устройство, висящее на KBD-порту i8042.
    "i8042.kbdreset=1"
    # Дополнительно сбрасываем драйвер AT-клавиатуры.
    "atkbd.reset"
  ];

  # Ранний ACPI override (аналог GRUB_EARLY_INITRD_LINUX_CUSTOM=acpi_override).
  # Здесь подменяется DSDT для PS2K: IRQ ActiveLow -> ActiveHigh.
  # Для этой машины (MAIBENBEN X677) это обход BIOS-ошибки клавиатуры.
  boot.initrd.prepend = lib.mkBefore [ "${x677AcpiOverride}" ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.connect-timeout = 5;
  nix.settings.stalled-download-timeout = 30;
  nix.settings.extra-substituters = [ "https://noctalia.cachix.org" ];
  nix.settings.extra-trusted-public-keys = [
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
  ];
  networking.hostName = "nixos"; # Define your hostname.

  


  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Yekaterinburg";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ru_RU.UTF-8";
    LC_IDENTIFICATION = "ru_RU.UTF-8";
    LC_MEASUREMENT = "ru_RU.UTF-8";
    LC_MONETARY = "ru_RU.UTF-8";
    LC_NAME = "ru_RU.UTF-8";
    LC_NUMERIC = "ru_RU.UTF-8";
    LC_PAPER = "ru_RU.UTF-8";
    LC_TELEPHONE = "ru_RU.UTF-8";
    LC_TIME = "ru_RU.UTF-8";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us,ru";
    variant = "";
    options = "grp:caps_toggle";
  };

  console = {
    # Linux TTY (Ctrl+Alt+F1..F6): US + RU, switch by CapsLock.
    keyMap = "ruwin_cplk-UTF-8";
    font = "cyr-sun16";
  };

  services.libinput = {
    enable = true;
    mouse = {
      accelProfile = "flat";
      scrollMethod = "button";
      scrollButton = 9; # Узнать айди можно через `xev -event button | grep button`
      middleEmulation = false;
    };
    touchpad = {
      accelProfile = "flat";
      middleEmulation = false;
    };
  };

  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
  };

  services.displayManager.gdm.enable = false;
  services.desktopManager.gnome.enable = false;
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd ${niriSessionWithWayland}";
      };
    };
  };

  

  programs.kdeconnect.enable = true;
  programs.niri.enable = true;
  # niri portal routing: keep GNOME backend available for screencast/remote-desktop
  # and let lightweight interfaces stay on GTK backend.
  xdg.portal.extraPortals = lib.mkForce [
    pkgs.gnome-keyring
    pkgs.xdg-desktop-portal-gtk
    pkgs.xdg-desktop-portal-gnome
  ];
  xdg.portal.config.niri = {
    default = [ "gnome" "gtk" ];
    "org.freedesktop.impl.portal.Access" = [ "gtk" ];
    "org.freedesktop.impl.portal.Notification" = [ "gtk" ];
    "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
  };
  services.gvfs.enable = true;
  services.tumbler.enable = true;
  services.noctalia-shell.enable = true;
  services.flatpak.enable = true;
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.fovendor = {
    isNormalUser = true;
    description = "fovendor";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.fovendor = { pkgs, ... }: {
      home.stateVersion = "25.11";
      home.file.".local/share/nautilus/scripts/Создать PDF из картинок" = {
        source = "${nautilusImagesToPdfScript}/bin/nautilus-create-images-pdf";
        executable = true;
      };
      home.pointerCursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Amber";
        size = 28;
        gtk.enable = true;
        x11.enable = true;
      };
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  fonts.packages = with pkgs; [
    montserrat
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
  ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    adwaita-icon-theme-legacy
    papirus-icon-theme
    colloid-icon-theme
    ghostty
    codeWaylandWrapper
    vscode
    unstablePkgs.amnezia-vpn
    firefox
    telegram-desktop
    mattermostDesktopPkg
    google-chrome
    obs-studio
    ffmpeg
    mpv
    grim
    slurp
    wl-clipboard
    (tesseract.override { enableLanguages = [ "eng" "rus" ]; })
    imagemagick
    zbar
    translate-shell
    wl-screenrec
    wf-recorder
    xwayland-satellite
    gifski
    superfile
    broot
    yazi
    libreoffice
    wget
    curl
    git
    sshfs
    polkit_gnome
    nautilus
    nautilusNativeExtensions
    sushi
    ffmpegthumbnailer
    gnome-epub-thumbnailer
    unstablePkgs.godot
    unstablePkgs.godot-export-templates-bin
    peazip
    gnome-text-editor
    gnome-calculator
    htop
    keepassxc
    python313
    gobject-introspection
    gobject-introspection.dev
    gtk3
    python313Packages.pygobject3
    webkitgtk_4_1
    img2pdf
    inkscape
    krita
    qimgv
    qbittorrent
    freshfetch
    btop
    blender
    evince
  ];

  environment.pathsToLink = lib.mkAfter [
    "/lib/nautilus/extensions-4"
    "/share/godot"
  ];
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      libGL
      vulkan-loader
      wayland
      libxkbcommon
      xorg.libX11
      xorg.libXcursor
      xorg.libXi
      xorg.libXrandr
      xorg.libXinerama
      xorg.libXext
      xorg.libXrender
      alsa-lib
    ];
  };

  programs.amnezia-vpn.enable = true;
  programs.amnezia-vpn.package = unstablePkgs.amnezia-vpn;

  # Electron/Chromium apps (VS Code, etc.) should prefer Wayland in niri sessions.
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    NAUTILUS_4_EXTENSION_DIR = "${nautilusNativeExtensions}/lib/nautilus/extensions-4";
  };

  # Force native Wayland capture path for flameshot on wlroots/niri.
  environment.etc."xdg/flameshot/flameshot.ini".text = ''
    [General]
    useGrimAdapter=true
  '';

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
    };
  };

  systemd.user.services.polkit-gnome-agent = {
    description = "Polkit GNOME Authentication Agent";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  systemd.user.services.niri-output-setup = {
    description = "Apply Niri output mode on login";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    path = with pkgs; [
      coreutils
      gnugrep
      niri
    ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -eu

      # Wait for the niri control socket and then set the panel mode.
      for _ in $(seq 1 40); do
        socket="$(ls /run/user/$UID/niri.*.sock 2>/dev/null | head -n1 || true)"
        if [ -n "$socket" ]; then
          export NIRI_SOCKET="$socket"
          if niri msg outputs | grep -q '(eDP-1)'; then
            niri msg output eDP-1 mode 1920x1200@165.015 || true
          fi
          exit 0
        fi
        sleep 0.25
      done

      exit 0
    '';
  };
  


  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  services.vader5d.enable = true;
  system.stateVersion = "25.11"; # Did you read the comment?

}
