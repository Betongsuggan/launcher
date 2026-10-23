# Shared by the Home Manager and NixOS modules: the fleet host type, the
# menu actions, and keybind rendering for each compositor.
{ lib }:
let
  inherit (lib) mkOption types;
in
rec {
  # The menus programs.launcher provides, in display order
  actions = [
    "applications"
    "webSearch"
    "symbols"
    "clipboard"
    "wifi"
    "bluetooth"
    "monitor"
    "audioOutput"
    "audioInput"
    "fleet"
  ];

  # One host of the fleet (services.fleet-status.hosts / programs.launcher.fleet.hosts)
  hostType = types.submodule (
    { name, config, ... }:
    let
      host = config;
    in
    {
      options = {
        address = mkOption {
          type = types.str;
          description = "DNS name or IP: where this host's status is fetched, and the default SSH target.";
          example = "laptop.tail1234.ts.net";
        };
        tailnetName = mkOption {
          type = types.nullOr types.str;
          default = name;
          defaultText = lib.literalMD "the attribute name";
          description = "The host's name in `tailscale status`, to tell online from offline. Null: never consult tailscale for it.";
        };
        tailnetIp = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "The host's tailnet IP: the address its announcements arrive from, and where announcements to it go (no DNS on the way down).";
          example = "100.100.1.2";
        };
        ssh = mkOption {
          type = types.nullOr (
            types.submodule (
              { config, ... }:
              {
                options = {
                  user = mkOption {
                    type = types.str;
                    description = "The account to log into.";
                  };
                  command = mkOption {
                    type = types.str;
                    default = "ssh ${config.user}@${host.address}";
                    defaultText = lib.literalMD "`ssh <user>@<address>`";
                    description = "The command that opens the shell (runs in the launcher's terminal).";
                  };
                };
              }
            )
          );
          default = null;
          description = "Where the dashboard's SSH action goes; null: no SSH action for this host.";
        };
        wake = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "A command that wakes this host (sends the magic packet from wherever it reaches it); null: no Wake action.";
          example = "ssh alice@server.tail1234.ts.net wakeonlan aa:bb:cc:dd:ee:ff";
        };
        power = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                on = mkOption {
                  type = types.str;
                  description = "Command that powers the host on.";
                };
                off = mkOption {
                  type = types.str;
                  description = "Command that cuts the host's power.";
                };
                status = mkOption {
                  type = types.str;
                  description = "Command printing `on` or `off` on its first line and, optionally, the draw in watts on a second.";
                };
              };
            }
          );
          default = null;
          description = "How the host's power is switched (a smart plug); null: no power actions.";
        };
        relay = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "The host (a key of `hosts`) this one tells before it suspends or shuts down; the dashboard reads the announcement from that host's status.";
        };
      };
    }
  );

  # "Mod+Ctrl+P" -> { mods = [ "Mod" "Ctrl" ]; key = "P"; }
  chord =
    c:
    let
      parts = lib.splitString "+" c;
    in
    {
      mods = lib.init parts;
      key = lib.last parts;
    };

  # Hyprland: "SUPER_SHIFT, a, exec, <cmd>"
  hyprlandBind =
    chordName: cmd:
    let
      c = chord chordName;
      mods = {
        Mod = "SUPER";
        Ctrl = "CTRL";
        Shift = "SHIFT";
        Alt = "ALT";
      };
      keys = {
        Return = "RETURN";
        Space = "SPACE";
        Minus = "minus";
        Equal = "equal";
        Comma = "comma";
        Period = "period";
      };
      key = keys.${c.key} or (if lib.stringLength c.key == 1 then lib.toLower c.key else c.key);
    in
    "${lib.concatMapStringsSep "_" (m: mods.${m}) c.mods}, ${key}, exec, ${cmd}";

  # sway: { "Mod4+Shift+a" = "exec <cmd>"; }
  swayBind =
    modifier: chordName: cmd:
    let
      c = chord chordName;
      mods = {
        Mod = modifier;
        Ctrl = "Ctrl";
        Shift = "Shift";
        Alt = "Mod1";
      };
      keys = {
        Space = "space";
        Minus = "minus";
        Equal = "equal";
        Comma = "comma";
        Period = "period";
      };
      key = keys.${c.key} or (if lib.stringLength c.key == 1 then lib.toLower c.key else c.key);
    in
    lib.nameValuePair (lib.concatStringsSep "+" (map (m: mods.${m}) c.mods ++ [ key ])) "exec ${cmd}";
}
