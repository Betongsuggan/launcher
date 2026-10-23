# programs.launcher.fleet: every host's status on one screen, with SSH,
# wake, power and a rebuild check for each, in the launcher.
{
  config,
  lib,
  pkgs,
  ...
}@args:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  osConfig = args.osConfig or null;
  cfg = config.programs.launcher.fleet;
  launcherLib = import ../../lib { inherit lib; };

  # A value from the NixOS side (services.fleet-status, nix, tailscale), or
  # the fallback when this is a standalone Home Manager configuration
  fromOs =
    path: fallback: if osConfig == null then fallback else lib.attrByPath path fallback osConfig;

  dashboard = pkgs.callPackage ../../pkgs/fleet-dashboard.nix { } {
    inherit (cfg)
      hosts
      self
      port
      flake
      ;
    dmenu = prompt: config.programs.launcher.dmenu { inherit prompt; };
    inherit (config.programs.launcher) terminal;
    tailscale = cfg.tailscalePackage;
    nix = cfg.nixPackage;
  };
in
{
  options.programs.launcher.fleet = {
    enable = mkEnableOption "the fleet dashboard";

    self = mkOption {
      type = types.nullOr types.str;
      default = fromOs [ "services" "fleet-status" "hostName" ] null;
      defaultText = lib.literalMD "the NixOS host's `services.fleet-status.hostName`";
      description = "This host's key in `hosts` (its row says \"(this)\" and its power can't be cut from here).";
    };

    hosts = mkOption {
      type = types.attrsOf launcherLib.hostType;
      default = fromOs [ "services" "fleet-status" "hosts" ] { };
      defaultText = lib.literalMD "the NixOS host's `services.fleet-status.hosts`";
      description = ''
        The hosts the dashboard shows. Defaults to the fleet defined on the
        NixOS side; a definition here replaces it wholesale (define it in
        full to differ per user).
      '';
    };

    port = mkOption {
      type = types.port;
      default = fromOs [ "services" "fleet-status" "port" ] 9099;
      defaultText = lib.literalMD "the NixOS host's `services.fleet-status.port`, else 9099";
      description = "The port every host serves its status on.";
    };

    flake = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/alice/nixos";
      description = ''
        A checkout of the flake the hosts are built from. "Check if a rebuild
        is needed" evaluates `<flake>#nixosConfigurations.<host>` there and
        compares it with the system the host runs. Null: no such action.
      '';
    };

    tailscalePackage = mkOption {
      type = types.package;
      default = fromOs [ "services" "tailscale" "package" ] pkgs.tailscale;
      defaultText = lib.literalMD "the NixOS host's tailscale, else `pkgs.tailscale`";
      description = "The tailscale CLI (`tailscale status` tells which hosts to ask).";
    };

    nixPackage = mkOption {
      type = types.package;
      default = fromOs [ "nix" "package" ] pkgs.nix;
      defaultText = lib.literalMD "the NixOS host's nix, else `pkgs.nix`";
      description = "The nix that evaluates `flake` for the rebuild check.";
    };

    package = mkOption {
      type = types.package;
      readOnly = true;
      description = "The `fleet-dashboard` command.";
    };
  };

  config = mkIf (config.programs.launcher.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.self != null && cfg.hosts ? ${cfg.self};
        message = "programs.launcher.fleet.self (${toString cfg.self}) must be a key of programs.launcher.fleet.hosts";
      }
      {
        assertion = lib.all (h: h.relay == null || cfg.hosts ? ${h.relay}) (lib.attrValues cfg.hosts);
        message = "every programs.launcher.fleet.hosts.<host>.relay must be a key of programs.launcher.fleet.hosts";
      }
    ];

    programs.launcher.fleet.package = dashboard;
    home.packages = [ dashboard ];
  };
}
