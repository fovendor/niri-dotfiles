{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkEnableOption mkOption types stringAfter;
  cfg = config.services.happ;
in
{
  options.services.happ = {
    enable = mkEnableOption "Happ proxy desktop client and background TUN daemon";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./happ.nix {
        inherit (cfg) forceXwayland forceSoftwareRendering;
      };
      defaultText = "pkgs.callPackage ./happ.nix { }";
      description = "The Happ package to use.";
    };

    forceXwayland = mkOption {
      type = types.bool;
      default = false;
      description = "Run Happ through XWayland instead of its bundled Wayland plugins.";
    };

    forceSoftwareRendering = mkOption {
      type = types.bool;
      default = false;
      description = "Force software rendering for the Happ Qt Quick interface.";
    };

    tunInterface = mkOption {
      type = types.str;
      default = "tun0";
      description = "Name of the TUN interface created by Happ.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      pkgs.net-tools
      pkgs.lsb-release
    ];

    # QSysInfo uses this legacy path for Happ's hardware identifier.
    systemd.tmpfiles.rules = [
      "L+ /var/lib/dbus/machine-id - - - - /etc/machine-id"
    ];

    networking.firewall.checkReversePath = "loose";
    networking.firewall.trustedInterfaces = [ cfg.tunInterface ];
    boot.kernelModules = [ "tun" ];

    # Happ hard-codes /opt/happ. Keep this root-owned because happd runs from it.
    system.activationScripts.happ-opt = stringAfter [ "stdio" ] ''
      stamp=/opt/happ/.nix-store-path
      if [ "$(cat "$stamp" 2>/dev/null)" != "${cfg.package}" ]; then
        rm -rf /opt/happ
        mkdir -p /opt/happ
        cp -r ${cfg.package}/happ/. /opt/happ/
        chown -R root:root /opt/happ
        chmod -R u=rwX,go=rX /opt/happ
        printf '%s' "${cfg.package}" > "$stamp"
      fi
    '';

    systemd.services.happd = {
      description = "Happ Process Control Daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ cfg.package ];
      path = with pkgs; [ iproute2 iptables procps net-tools ];

      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        ExecStart = "/opt/happ/bin/happd";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "10s";
        KillMode = "mixed";
        KillSignal = "SIGTERM";
      };
    };
  };
}
