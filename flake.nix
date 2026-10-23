{
  description = "A launcher with wifi, bluetooth, audio and monitor menus, and a fleet dashboard, as Home Manager and NixOS modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Only the `windowManager = "niri"` check imports it; the modules never
    # do, so a consumer's own niri-flake is the only one declaring programs.niri
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sources of the menus, built against the consumer's nixpkgs (pkgs/)
    audiomenu = {
      url = "github:Betongsuggan/audiomenu";
      flake = false;
    };
    monitormenu = {
      url = "github:Betongsuggan/monitormenu";
      flake = false;
    };

    # Upstream vicinae extensions, pinned: later revisions add a native npm
    # module (usocket) to the bluetooth extension whose node-gyp build fails
    vicinae-extensions = {
      url = "github:vicinaehq/extensions/b698ce7ecb58dec1efe297f87370253d8f6ba9d5";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      lib = import ./lib { inherit (nixpkgs) lib; };

      homeModules.default = import ./modules/home { inherit inputs; };
      homeManagerModules = self.homeModules;
      nixosModules.default = import ./modules/nixos { inherit inputs; };

      overlays.default =
        final: _:
        import ./pkgs {
          pkgs = final;
          inherit inputs;
        };

      packages = forAllSystems (
        pkgs:
        let
          p = import ./pkgs { inherit pkgs inputs; };
        in
        {
          inherit (p) audiomenu monitormenu;
          vicinae-wifi-commander = p.vicinae-extension "wifi-commander";
          vicinae-bluetooth = p.vicinae-extension "bluetooth";
        }
      );

      # `nix flake check --no-build` evaluates every variant; without
      # --no-build the Home Manager ones build their whole closure
      checks = forAllSystems (pkgs: import ./checks { inherit self inputs pkgs; });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
