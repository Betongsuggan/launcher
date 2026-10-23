# programs.launcher.keybinds: one chord per menu, rendered into the
# compositor's own Home Manager options.
{
  config,
  lib,
  options,
  ...
}:
let
  inherit (lib)
    getExe
    mkIf
    mkOption
    types
    ;
  cfg = config.programs.launcher;
  launcherLib = import ../../lib { inherit lib; };

  defaults = {
    applications = "Mod+O";
    webSearch = "Mod+D";
    symbols = "Mod+E";
    clipboard = "Mod+C";
    wifi = "Mod+U";
    bluetooth = "Mod+Z";
    monitor = "Mod+M";
    audioOutput = "Mod+A";
    audioInput = "Mod+Shift+A";
    fleet = "Mod+G";
  };

  # chord -> command, for the menus that exist and have a chord
  binds = lib.listToAttrs (
    lib.concatMap (
      action:
      lib.optional (cfg.keybinds.${action} != null && cfg.menus.${action} != null) (
        lib.nameValuePair cfg.keybinds.${action} "${getExe cfg.package} ${action}"
      )
    ) launcherLib.actions
  );

  hasNiri = options.programs ? niri;
in
{
  options.programs.launcher.keybinds = mkOption {
    type = types.submodule {
      options = {
        enable = mkOption {
          type = types.bool;
          default = cfg.windowManager != null;
          defaultText = lib.literalMD "true when `windowManager` is set";
          description = "Write the binds into the compositor's configuration.";
        };
      }
      // lib.mapAttrs (
        action: chord:
        mkOption {
          type = types.nullOr types.str;
          default = chord;
          description = "Chord that opens the ${action} menu, in niri notation (Mod, Ctrl, Shift, Alt); null leaves it unbound.";
        }
      ) defaults;
    };
    default = { };
    description = "Keybinds for the menus. A chord is bound only when its menu exists.";
  };

  config = mkIf (cfg.enable && cfg.keybinds.enable) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.windowManager == "niri" -> hasNiri;
            message = "programs.launcher.windowManager = \"niri\" needs niri-flake's Home Manager module (programs.niri) imported";
          }
        ];

        wayland.windowManager.hyprland.settings.bind = mkIf (cfg.windowManager == "hyprland") (
          lib.mapAttrsToList launcherLib.hyprlandBind binds
        );

        # On top of sway's default keymap (the same priority Home Manager gives it)
        wayland.windowManager.sway.config.keybindings = mkIf (cfg.windowManager == "sway") (
          lib.mkOptionDefault (
            lib.mapAttrs' (launcherLib.swayBind config.wayland.windowManager.sway.config.modifier) binds
          )
        );
      }
      (lib.optionalAttrs hasNiri {
        programs.niri.settings.binds = mkIf (cfg.windowManager == "niri") (
          lib.mapAttrs (_: cmd: {
            action.spawn = lib.splitString " " cmd;
          }) binds
        );
      })
    ]
  );
}
