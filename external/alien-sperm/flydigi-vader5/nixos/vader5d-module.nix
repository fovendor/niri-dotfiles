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
