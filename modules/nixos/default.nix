# services.fleet-status: this host's status as JSON for the fleet dashboard,
# and the announcements it makes before suspending or shutting down.
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;
  cfg = config.services.fleet-status;
  launcherLib = import ../../lib { inherit lib; };

  peersByIp = lib.mapAttrs' (name: h: lib.nameValuePair h.tailnetIp name) (
    lib.filterAttrs (_: h: h.tailnetIp != null) cfg.hosts
  );

  status = pkgs.callPackage ../../pkgs/fleet-status.nix { } {
    inherit (cfg) hostName backupUnits;
    inherit peersByIp;
  };

  relay = cfg.hosts.${cfg.announceTo} or null;
  announce = pkgs.callPackage ../../pkgs/fleet-announce.nix { } {
    relay = cfg.announceTo;
    relayAddress = if relay.tailnetIp != null then relay.tailnetIp else relay.address;
    inherit (cfg) port;
  };
in
{
  options.services.fleet-status = {
    enable = mkEnableOption ''
      serving this host's status (battery, disk, uptime, backups, running
      system, what peers last announced) as JSON for the fleet dashboard,
      and accepting peers' suspend/shutdown announcements. Socket activated:
      nothing runs between requests
    '';

    hostName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "This host's name: the `host` field of its status, and its key in `hosts`.";
    };

    port = mkOption {
      type = types.port;
      default = 9099;
      description = "The TCP port the status is served on (every host of a fleet uses the same).";
    };

    hosts = mkOption {
      type = types.attrsOf launcherLib.hostType;
      default = { };
      description = ''
        The fleet, by name. Defined once here; the dashboard
        (`programs.launcher.fleet.hosts`) defaults to it. A host's `tailnetIp`
        is what identifies its announcements; a host without one cannot announce.
      '';
    };

    announceTo = mkOption {
      type = types.nullOr types.str;
      default = cfg.hosts.${cfg.hostName}.relay or null;
      defaultText = lib.literalMD "this host's `relay` in `hosts`, if any";
      description = ''
        A host (a key of `hosts`) to tell before suspending or shutting down,
        and after resuming, so the dashboard can show "asleep" or "shut down"
        instead of tailscale's "offline". The natural choice is the host that
        wakes this one, which is always on while this one is not.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open `port` in the firewall, on `interface` only when set.";
    };

    interface = mkOption {
      type = types.nullOr types.str;
      default =
        if config.services.tailscale.enable then config.services.tailscale.interfaceName else null;
      defaultText = lib.literalMD "the tailscale interface when tailscale is on, else null";
      description = "The interface the port is opened on; null opens it on every interface.";
    };

    backupUnits = mkOption {
      type = types.listOf types.str;
      default = map (n: "restic-backups-${n}") (lib.attrNames config.services.restic.backups);
      defaultText = lib.literalMD "this host's `services.restic.backups` units";
      description = "systemd units whose last run and result are reported as `backups`.";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.announceTo == null || cfg.hosts ? ${cfg.announceTo};
          message = "services.fleet-status.announceTo (${toString cfg.announceTo}) is not a key of services.fleet-status.hosts";
        }
      ];

      systemd.sockets.fleet-status = {
        description = "Fleet status";
        wantedBy = [ "sockets.target" ];
        listenStreams = [ (toString cfg.port) ];
        socketConfig.Accept = true;
      };

      systemd.services."fleet-status@" = {
        description = "Fleet status response";
        serviceConfig = {
          ExecStart = lib.getExe status;
          StandardInput = "socket";
          StandardOutput = "socket";
          StandardError = "journal";
          DynamicUser = true;
          # Peers' announcements, one file per host
          StateDirectory = "fleet-status";
          RuntimeMaxSec = 10;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };

      networking.firewall = mkIf cfg.openFirewall (
        if cfg.interface == null then
          { allowedTCPPorts = [ cfg.port ]; }
        else
          { interfaces.${cfg.interface}.allowedTCPPorts = [ cfg.port ]; }
      );
    })

    (mkIf (cfg.enable && cfg.announceTo != null) {
      environment.systemPackages = [ announce ];

      # Before any sleep; sleep.target is not part of a shutdown, so a
      # suspend never masquerades as one
      systemd.services.fleet-announce-sleep = {
        description = "Tell ${cfg.announceTo} this host is suspending";
        wantedBy = [ "sleep.target" ];
        before = [ "sleep.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe announce} suspend";
        };
      };

      # Clears the "asleep" the moment the host is back, before tailscale
      # has reconnected
      powerManagement.resumeCommands = "${lib.getExe announce} resume || true";

      # Stops (so announces) on the way down, while the network is still up:
      # units stop in reverse start order, and this one starts after it
      systemd.services.fleet-announce-shutdown = {
        description = "Tell ${cfg.announceTo} this host is shutting down";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
        ]
        ++ lib.optional config.services.tailscale.enable "tailscaled.service";
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
          ExecStop = "${lib.getExe announce} shutdown";
          TimeoutStopSec = 5;
        };
      };
    })
  ];
}
