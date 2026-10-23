# One standalone Home Manager evaluation per windowManager value (no
# osConfig, so every NixOS-derived default takes its fallback), one NixOS
# evaluation of the status server, and the two extension builds.
{
  self,
  inputs,
  pkgs,
}:
let
  inherit (pkgs) lib;
  fleet = {
    enable = true;
    self = "a";
    hosts = {
      a = {
        address = "a.example";
        tailnetIp = "100.64.0.1";
      };
      b = {
        address = "b.example";
        tailnetIp = "100.64.0.2";
        ssh.user = "test";
        relay = "a";
        wake = "ssh test@a.example wake-b";
        power = {
          on = "plug-b on";
          off = "plug-b off";
          status = "plug-b status";
        };
      };
    };
  };

  homeConfig =
    windowManager:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeModules.default
        {
          home = {
            username = "test";
            homeDirectory = "/home/test";
            stateVersion = "26.05";
          };
          programs.launcher = {
            enable = true;
            inherit windowManager fleet;
            terminal = "alacritty -e";
          };
          wayland.windowManager.hyprland.enable = windowManager == "hyprland";
          wayland.windowManager.sway.enable = windowManager == "sway";
        }
      ]
      ++ lib.optionals (windowManager == "niri") [
        inputs.niri.homeModules.niri
        { programs.niri.enable = true; }
      ];
    };
  home = windowManager: (homeConfig windowManager).activationPackage;

  nixos =
    (inputs.nixpkgs.lib.nixosSystem {
      inherit (pkgs.stdenv.hostPlatform) system;
      modules = [
        self.nixosModules.default
        {
          networking.hostName = "b";
          services.tailscale.enable = true;
          services.fleet-status = {
            enable = true;
            inherit (fleet) hosts;
          };
          fileSystems."/" = {
            device = "/dev/null";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = "26.05";
        }
      ];
    }).config.system.build.toplevel;
in
{
  hm-none = home null;
  hm-hyprland = home "hyprland";
  hm-niri = home "niri";
  hm-sway = home "sway";
  inherit nixos;
  # The generated scripts on their own (building them runs shellcheck)
  launcher-menu = (homeConfig null).config.programs.launcher.package;
  fleet-dashboard = (homeConfig null).config.programs.launcher.fleet.package;
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) vicinae-wifi-commander vicinae-bluetooth;
}
