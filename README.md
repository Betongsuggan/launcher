# launcher

A launcher for Wayland desktops as a Home Manager module, with the menus that
make it a control panel, and a fleet dashboard that shows every host you own
on one screen. Self-contained: the flake pins every tool it runs
([vicinae](https://vicinae.com), [audiomenu](https://github.com/Betongsuggan/audiomenu),
[monitormenu](https://github.com/Betongsuggan/monitormenu), wiremix, tailscale, jq, ...);
nothing has to be installed beforehand.

| Menu | Default chord | What it does |
|---|---|---|
| applications | Mod+O | the launcher's root view |
| webSearch | Mod+D | the root view (vicinae searches the web from there) |
| symbols | Mod+E | emoji and symbol search |
| clipboard | Mod+C | clipboard history |
| wifi | Mod+U | join a network (wifi-commander extension; nmcli or iwctl) |
| bluetooth | Mod+Z | pair and connect devices (bluetooth extension; bluez) |
| monitor | Mod+M | resolution, scale, rotation, placement, VRR, on/off of an output (Hyprland, niri) |
| audioOutput / audioInput | Mod+A / Mod+Shift+A | default device, per-application volume, a full mixer (wiremix) |
| fleet | Mod+G | every host's status; SSH, wake, power on/off, rebuild check, details |

Every menu is also a command: `launcher-menu <name>` (no argument lists them).

## Setup

Add the flake and import its two modules; the Home Manager one as a NixOS
module (`home-manager.sharedModules`) or in a standalone Home Manager
configuration.

```nix
inputs.launcher = {
  url = "github:Betongsuggan/launcher";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};
```

```nix
# NixOS: nixosSystem modules
launcher.nixosModules.default
home-manager.nixosModules.home-manager
{ home-manager.sharedModules = [ launcher.homeModules.default ]; }
```

```nix
# Home Manager (the user)
wayland.windowManager.hyprland.enable = true;   # windowManager is detected from this
programs.launcher = {
  enable = true;
  terminal = "alacritty -e";
  keybinds.fleet = "Mod+Shift+G";
  fleet.enable = true;
  fleet.flake = "/home/alice/nixos";
};
```

```nix
# NixOS (the host): the fleet, defined once, and this host's status server
services.fleet-status = {
  enable = true;
  hosts = {
    laptop  = { address = "laptop.tail1234.ts.net";  tailnetIp = "100.100.1.2"; relay = "server"; };
    server  = { address = "server.tail1234.ts.net";  tailnetIp = "100.100.1.1"; ssh.user = "alice"; };
    desktop = { address = "desktop.tail1234.ts.net"; tailnetIp = "100.100.1.3"; ssh.user = "alice"; relay = "server";
                wake = "ssh alice@server.tail1234.ts.net wakeonlan aa:bb:cc:dd:ee:ff"; };
  };
};
```

`examples/` is a complete host built this way. Requirements: nixpkgs and Home
Manager 25.11 or later (for `programs.vicinae` and `pkgs.vicinae`), a Wayland
compositor. The wifi menu needs NetworkManager (`networking.networkmanager.enable`)
or iwd on the host, the bluetooth menu bluez (`hardware.bluetooth.enable`), the
fleet dashboard a tailnet (or at least hosts that resolve by `address`).

## Options

### `programs.launcher` (Home Manager)

| Option | Type | Default | Description |
|---|---|---|---|
| enable | bool | false | |
| backend | enum `vicinae` | `vicinae` | The launcher that draws the menus |
| windowManager | null or `hyprland` `niri` `sway` | the compositor enabled in this configuration | What the keybinds are rendered for; null writes none |
| terminal | str | `xdg-terminal-exec` | Runs the rest of its arguments in a terminal (`alacritty -e`, `foot`, ...) |
| audiomenu.package, monitormenu.package | package | built from the pinned sources | |
| keybinds.enable | bool | `windowManager != null` | Write the binds into the compositor's config |
| keybinds.\<menu\> | null or str | the table above | Chord in niri notation (`Mod`, `Ctrl`, `Shift`, `Alt` + key); null leaves it unbound. A chord is bound only when its menu exists |
| vicinae.settings | JSON | `{}` | Merged into `programs.vicinae.settings`. settings.json is a read-only store link: changes in vicinae's settings window don't persist, set them here |
| vicinae.upstreamExtensions | list of str | wifi-commander, bluetooth | Extensions of the pinned [vicinaehq/extensions](https://github.com/vicinaehq/extensions) to build |
| vicinae.extensions | list of package | `[]` | Further, pre-built extensions |
| vicinae.themes | TOML | `{}` | Extra themes by file name |
| vicinae.useLayerShell | bool | true | |
| vicinae.fileIndex.enable / paths / exclude | bool / list / list | false / `~` / `[]` | The background file indexer (walks hidden directories too; off by default) |
| vicinae.networkTool | `nmcli` or `iwctl` | from the NixOS host, else nmcli | What the wifi menu drives |
| fleet.enable | bool | false | |
| fleet.self | null or str | the host's `services.fleet-status.hostName` | This host's key in `hosts` |
| fleet.hosts | attrs of host | the host's `services.fleet-status.hosts` | The hosts shown; a definition here replaces the NixOS one wholesale |
| fleet.port | port | the host's, else 9099 | |
| fleet.flake | null or str | null | Checkout the rebuild check evaluates `#nixosConfigurations.<host>` in |
| fleet.tailscalePackage, fleet.nixPackage | package | the host's, else nixpkgs' | |
| dmenu | function (read-only) | | `{ prompt ? null, additionalArgs ? [] }` -> a command reading lines on stdin, printing the choice |
| menus | attrs (read-only) | | One command per menu, null when unavailable |
| package | package (read-only) | | `launcher-menu` |

### `services.fleet-status` (NixOS)

| Option | Type | Default | Description |
|---|---|---|---|
| enable | bool | false | Serve this host's status and accept peers' announcements |
| hostName | str | `networking.hostName` | This host's key in `hosts` |
| port | port | 9099 | |
| hosts | attrs of host | `{}` | The fleet (see below) |
| announceTo | null or str | this host's `relay` | Host told before suspend/shutdown and after resume (`fleet-announce suspend|shutdown|resume`) |
| openFirewall | bool | true | |
| interface | null or str | the tailscale interface, else null (all) | Where the port is opened |
| backupUnits | list of str | the host's restic jobs | Units reported as `backups` |

### A host (`hosts.<name>`)

| Field | Default | Description |
|---|---|---|
| address | | DNS name or IP: the status URL and the default SSH target |
| tailnetName | the attribute name | Its name in `tailscale status`; null: never consult tailscale for it |
| tailnetIp | null | Identifies its announcements; where announcements to it go (no DNS on the way down) |
| ssh.user, ssh.command | null, `ssh <user>@<address>` | The SSH action; null: none |
| wake | null | A command that sends it a magic packet; null: no Wake |
| power.on / off / status | null | Commands switching its power (a smart plug); `status` prints `on` or `off`, optionally watts on a second line |
| relay | null | The host it announces to; the dashboard reads `peers.<name>` from that host's status |

## How the fleet view works

- Each host serves a small JSON document (battery, disk, uptime, backups,
  running system, reboot pending, when it was rebuilt, what peers announced)
  from a socket-activated unit: nothing runs between requests. The firewall
  opens the port on the tailscale interface only.
- Before suspending or shutting down a host POSTs its state to its relay,
  which identifies it by tailnet IP; the dashboard then shows *asleep since*
  or *shut down since* instead of tailscale's bare *offline*. With a plug,
  *no power* when its relay is open, and the draw in watts otherwise.
- The dashboard asks the hosts tailscale sees online, in parallel with a 2 s
  timeout, and offers for the chosen one what its entry allows: SSH, Wake
  (refused while the plug is off), Power on / off (asks first; refused for
  the host it runs on), the rebuild check (`fleet.flake`), Details, Copy address.

## Development

`nix flake check --no-build` evaluates a standalone Home Manager configuration
per `windowManager` value and a NixOS host; `nix build .#vicinae-wifi-commander`
builds an extension. `nix fmt` formats.
