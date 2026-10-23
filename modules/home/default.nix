# programs.launcher: a launcher (vicinae) with wifi, bluetooth, audio and
# monitor menus, a fleet dashboard, and the keybinds that open them.
{ inputs }:
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
let
  inherit (lib)
    escapeShellArg
    getExe
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.programs.launcher;
  launcherLib = import ../../lib { inherit lib; };
  launcherPkgs = import ../../pkgs { inherit pkgs inputs; };

  # Menus every backend gets the same way: the tool draws its list in the
  # chosen launcher. audiomenu's last entry opens wiremix, a full PipeWire
  # mixer, in the terminal.
  genericMenus = backend: {
    audioOutput = "${getExe cfg.audiomenu.package} sink --launcher ${backend} --mixer ${escapeShellArg "${cfg.terminal} ${getExe pkgs.wiremix}"}";
    audioInput = "${getExe cfg.audiomenu.package} source --launcher ${backend} --mixer ${escapeShellArg "${cfg.terminal} ${getExe pkgs.wiremix}"}";
    # monitormenu drives Hyprland and niri; it detects the running one itself
    monitor =
      if cfg.windowManager == "sway" then
        null
      else
        "${getExe cfg.monitormenu.package} --launcher ${backend}"
        + lib.optionalString (cfg.windowManager != null) " --backend ${cfg.windowManager}";
  };

  # What each backend provides: its dmenu and its own menus. A menu a backend
  # lacks is null, and nothing binds it.
  backends = {
    vicinae = {
      inherit (cfg.vicinae) dmenu;
      menus = genericMenus "vicinae" // cfg.vicinae.menus;
    };
  };
  backend = backends.${cfg.backend};

  menus = lib.genAttrs launcherLib.actions (a: backend.menus.${a} or null) // {
    fleet = if cfg.fleet.enable then getExe cfg.fleet.package else null;
  };
  available = lib.filterAttrs (_: cmd: cmd != null) menus;

  # `launcher-menu <action>`: the stable command behind every keybind
  dispatcher = pkgs.writeShellApplication {
    name = "launcher-menu";
    text = ''
      case "''${1:-}" in
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (a: cmd: "  ${a}) exec ${cmd} ;;") available)}
        "")
          printf '%s\n' ${lib.escapeShellArgs (lib.attrNames available)}
          ;;
        *)
          echo "launcher-menu: no menu '$1' (run without arguments for the list)" >&2
          exit 64
          ;;
      esac
    '';
  };
in
{
  imports = [
    (import ./vicinae.nix { inherit inputs; })
    ./keybinds.nix
    ./fleet.nix
  ];

  options.programs.launcher = {
    enable = mkEnableOption "the launcher, its menus and the fleet dashboard";

    backend = mkOption {
      type = types.enum [ "vicinae" ];
      default = "vicinae";
      description = "The launcher that draws the menus.";
    };

    windowManager = mkOption {
      type = types.nullOr (
        types.enum [
          "hyprland"
          "niri"
          "sway"
        ]
      );
      default =
        if config.wayland.windowManager.hyprland.enable then
          "hyprland"
        else if config.wayland.windowManager.sway.enable then
          "sway"
        else if (options.programs ? niri) && config.programs.niri.enable then
          "niri"
        else
          null;
      defaultText = lib.literalMD "the compositor enabled in this Home Manager configuration, else null";
      description = ''
        The compositor the keybinds are rendered for and the monitor menu
        drives. Null: no keybinds are written; bind `launcher-menu <action>`
        yourself.
      '';
    };

    terminal = mkOption {
      type = types.str;
      default = getExe pkgs.xdg-terminal-exec;
      defaultText = lib.literalExpression "lib.getExe pkgs.xdg-terminal-exec";
      example = "alacritty -e";
      description = "A command that runs the rest of its arguments in a new terminal window (the audio mixer, the fleet SSH action).";
    };

    audiomenu.package = mkOption {
      type = types.package;
      default = launcherPkgs.audiomenu;
      defaultText = lib.literalMD "built from the flake's pinned source against `pkgs`";
      description = "The audiomenu package (audio device and per-application volume menus).";
    };

    monitormenu.package = mkOption {
      type = types.package;
      default = launcherPkgs.monitormenu;
      defaultText = lib.literalMD "built from the flake's pinned source against `pkgs`";
      description = "The monitormenu package (output configuration menu).";
    };

    dmenu = mkOption {
      type = types.functionTo types.str;
      readOnly = true;
      description = ''
        `{ prompt ? null, additionalArgs ? [ ], ... }` -> a command that reads
        lines on stdin and prints the chosen one, for other modules' menus.
      '';
    };

    menus = mkOption {
      type = types.attrsOf (types.nullOr types.str);
      readOnly = true;
      description = ''
        One command per menu (${lib.concatStringsSep ", " launcherLib.actions});
        null when the backend has no such menu, the extension providing it is
        not installed, or (`fleet`) the dashboard is off.
      '';
    };

    package = mkOption {
      type = types.package;
      readOnly = true;
      description = "`launcher-menu <action>`: opens that menu; lists them without an argument. What the keybinds run.";
    };
  };

  config = mkIf cfg.enable {
    programs.launcher = {
      inherit (backend) dmenu;
      inherit menus;
      package = dispatcher;
    };

    home.packages = [
      dispatcher
      cfg.audiomenu.package
      cfg.monitormenu.package
    ];
  };
}
