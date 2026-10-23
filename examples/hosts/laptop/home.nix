# The user: Hyprland with the launcher's menus on Mod+O/D/E/C/U/Z/M/A/Shift+A
# and the fleet dashboard on Mod+Shift+G.
{ ... }:
{
  home.stateVersion = "26.05";

  # programs.launcher.windowManager is detected from this
  wayland.windowManager.hyprland.enable = true;

  programs.launcher = {
    enable = true;
    terminal = "alacritty -e"; # for the audio mixer and the fleet SSH action
    keybinds.fleet = "Mod+Shift+G"; # any menu can be rebound, or set to null
    fleet = {
      enable = true; # hosts and self come from services.fleet-status
      flake = "/home/alice/nixos"; # enables "Check if a rebuild is needed"
    };
  };

  programs.alacritty.enable = true;
}
