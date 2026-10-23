# The host: a tailnet member running Hyprland, serving its status to the
# fleet and announcing to `server` before it sleeps.
{ pkgs, ... }:
{
  networking.hostName = "laptop";
  networking.networkmanager.enable = true; # the wifi menu drives nmcli
  hardware.bluetooth.enable = true; # the bluetooth menu drives bluetoothctl
  services.tailscale.enable = true;
  programs.hyprland.enable = true;

  services.fleet-status = {
    enable = true; # status on :9099, tailscale interface only
    hosts = {
      laptop = {
        address = "laptop.tail1234.ts.net";
        tailnetIp = "100.100.1.2";
        relay = "server"; # tell server before suspending or shutting down
      };
      server = {
        address = "server.tail1234.ts.net";
        tailnetIp = "100.100.1.1";
        ssh.user = "alice";
      };
      desktop = {
        address = "desktop.tail1234.ts.net";
        tailnetIp = "100.100.1.3";
        ssh.user = "alice";
        relay = "server";
        # Any command that reaches the host's network with a magic packet
        wake = "ssh alice@server.tail1234.ts.net ${pkgs.wakeonlan}/bin/wakeonlan aa:bb:cc:dd:ee:ff";
      };
    };
  };

  users.users.alice = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  # Illustrative only: a real host has its hardware configuration, a boot
  # loader and file systems
  fileSystems."/".device = "/dev/disk/by-label/nixos";
  boot.loader.systemd-boot.enable = true;
  system.stateVersion = "26.05";
}
