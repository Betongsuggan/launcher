# The vicinae backend: Home Manager's programs.vicinae, the upstream wifi and
# bluetooth extensions, and the deeplinks that open each menu.
{ inputs }:
{
  config,
  lib,
  pkgs,
  options,
  ...
}@args:
let
  inherit (lib)
    concatStringsSep
    escapeShellArg
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    ;
  osConfig = args.osConfig or null;
  cfg = config.programs.launcher;
  vcfg = cfg.vicinae;
  launcherPkgs = import ../../pkgs { inherit pkgs inputs; };
  vicinae = lib.getExe config.programs.vicinae.package;
  hasExtension = name: lib.elem name vcfg.upstreamExtensions;

  # vicinae's dmenu has no flags for password, case-insensitive, multi-select
  # or image modes; those arguments are accepted and ignored
  dmenu =
    {
      prompt ? null,
      additionalArgs ? [ ],
      ...
    }:
    concatStringsSep " " (
      [ "${vicinae} dmenu" ] ++ optional (prompt != null) "-p ${escapeShellArg prompt}" ++ additionalArgs
    );

  # The daemon must be running; menus are opened through deeplinks. An
  # extension's provider id is `@<author>/<name>` from its package.json.
  deeplink = path: "${vicinae} deeplink vicinae://${path}";
  menus = {
    applications = deeplink "toggle";
    # vicinae searches the web from its root view
    webSearch = deeplink "toggle";
    symbols = deeplink "launch/core/search-emojis";
    clipboard = deeplink "launch/clipboard/history";
    wifi =
      if hasExtension "wifi-commander" then
        deeplink "launch/@dagimg-dot/wifi-commander/scan-wifi"
      else
        null;
    bluetooth = if hasExtension "bluetooth" then deeplink "launch/@Gelei/bluetooth/devices" else null;
  };
in
{
  options.programs.launcher.vicinae = {
    settings = mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      description = ''
        Extra vicinae settings, merged into `programs.vicinae.settings`
        (`~/.config/vicinae/settings.json`). The file is a read-only store
        link, so changes made in vicinae's settings window don't persist:
        everything, provider preferences included, is set here.
      '';
    };

    upstreamExtensions = mkOption {
      type = types.listOf types.str;
      default = [
        "wifi-commander"
        "bluetooth"
      ];
      description = ''
        Extensions of the pinned vicinaehq/extensions repository to build and
        install, by directory name. wifi-commander provides the wifi menu
        (needs NetworkManager or iwd on the host), bluetooth the bluetooth
        menu (needs bluez).
      '';
    };

    extensions = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Further extensions, already built (e.g. with `config.lib.vicinae.mkExtension`).";
    };

    themes = mkOption {
      type = (pkgs.formats.toml { }).type;
      default = { };
      description = "Extra vicinae themes (TOML), keyed by theme file name.";
    };

    useLayerShell = mkOption {
      type = types.bool;
      default = true;
      description = "Whether vicinae should use the layer shell.";
    };

    fileIndex = {
      enable = mkEnableOption ''
        vicinae's background file indexer (file search). It walks every
        configured path, hidden directories included, and re-sweeps them
        periodically, so it is off unless enabled
      '';
      paths = mkOption {
        type = types.listOf types.str;
        default = [ config.home.homeDirectory ];
        defaultText = lib.literalExpression "[ config.home.homeDirectory ]";
        description = "Directories to index.";
      };
      exclude = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Directories to leave out of the index.";
      };
    };

    networkTool = mkOption {
      type = types.enum [
        "nmcli"
        "iwctl"
      ];
      default =
        if osConfig != null && !(osConfig.networking.networkmanager.enable or true) then
          "iwctl"
        else
          "nmcli";
      defaultText = lib.literalMD "`nmcli`, or `iwctl` when the NixOS host has NetworkManager off";
      description = "The CLI the wifi menu drives (a required preference of wifi-commander).";
    };

    dmenu = mkOption {
      type = types.functionTo types.str;
      internal = true;
      readOnly = true;
      description = "vicinae's dmenu command builder.";
    };

    menus = mkOption {
      type = types.attrsOf (types.nullOr types.str);
      internal = true;
      readOnly = true;
      description = "The menus vicinae itself provides.";
    };
  };

  # mkMerge, not `//`: both halves define `programs`
  config = mkIf (cfg.enable && cfg.backend == "vicinae") (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = options.programs ? vicinae;
            message = "programs.launcher needs Home Manager's programs.vicinae module (Home Manager 25.11 or later)";
          }
          {
            assertion = pkgs ? vicinae;
            message = "programs.launcher needs pkgs.vicinae (nixpkgs 25.11 or later)";
          }
        ];

        programs.launcher.vicinae = {
          inherit dmenu menus;
        };
      }
      (lib.optionalAttrs (options.programs ? vicinae) {
        programs.vicinae = {
          enable = true;
          # Started with the graphical session, whichever compositor runs it
          systemd.enable = true;
          extensions = map launcherPkgs.vicinae-extension vcfg.upstreamExtensions ++ vcfg.extensions;
          inherit (vcfg) themes;

          settings = lib.mkMerge [
            {
              launcher_window.layer_shell.enabled = vcfg.useLayerShell;
              providers.files.preferences = {
                autoIndexing = vcfg.fileIndex.enable;
                indexingPaths = vcfg.fileIndex.paths;
                excludedIndexingPaths = vcfg.fileIndex.exclude;
              };
            }
            (mkIf (hasExtension "wifi-commander") {
              # Required, otherwise asked for on first launch
              providers."@dagimg-dot/wifi-commander".preferences.network-cli-tool = vcfg.networkTool;
            })
            vcfg.settings
          ];
        };
      })
    ]
  );
}
