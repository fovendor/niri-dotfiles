{ config, lib, pkgs, ... }:

let
  cfg = config.services.vader5d;
  defaultPackage = pkgs.callPackage ./package.nix { };
  configArg = lib.optionalString (cfg.configFile != null) " --config ${cfg.configFile}";
in {
  options.services.vader5d = {
    enable = lib.mkEnableOption "Flydigi Vader 5 Pro userspace daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "Package providing `vader5d` and `vader5-debug`.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/vader5/config.toml";
      description = "Optional config path passed to `vader5d --config` for every device instance.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Godot/SDL can bind all Vader 5 buttons directly in standard mode.
    # Xbox Elite emulation reorders the extended button range.
    environment.etc = lib.mkIf (cfg.configFile == null) {
      "vader5/config.toml".text = builtins.replaceStrings
        [ "emulate_elite = true" ]
        [ "emulate_elite = false" ]
        (builtins.readFile ../config/config.toml);
    };

    # uaccess must precede 73-seat-late.rules. extraRules lands in 99-local
    # and leaves the game without an ACL even though the tag is present.
    services.udev.packages = [
      (pkgs.writeTextFile {
        name = "flydigi-vader5-hid-access";
        destination = "/lib/udev/rules.d/60-flydigi-vader5.rules";
        text = ''
          ACTION=="add|change", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="37d7", ATTRS{idProduct}=="2401", MODE="0660", TAG+="uaccess"
        '';
      })
    ];

    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="37d7", ATTRS{idProduct}=="2401", MODE="0660", TAG+="uaccess"
      ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="04b4", MODE="0660", TAG+="uaccess"
      ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="37d7", ATTRS{idProduct}=="2401", IMPORT{builtin}="usb_id"
      ACTION=="add", SUBSYSTEM=="hidraw", ENV{ID_VENDOR_ID}=="37d7", ENV{ID_MODEL_ID}=="2401", ATTRS{bInterfaceNumber}=="01", TAG+="systemd", ENV{SYSTEMD_WANTS}+="vader5d@%k.service"
    '';

    systemd.services."vader5d@" = {
      description = "Flydigi Vader 5 Pro Driver %I";
      bindsTo = [ "dev-%i.device" ];
      after = [ "dev-%i.device" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/vader5d --device %I${configArg}";
        Restart = "on-failure";
        RestartSec = 3;
        Nice = -10;
      };
    };
  };
}
