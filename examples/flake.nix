{
  description = "A NixOS host with the launcher and the fleet dashboard";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    launcher = {
      url = "github:Betongsuggan/launcher";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      launcher,
      ...
    }:
    {
      nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/laptop/configuration.nix
          launcher.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              sharedModules = [ launcher.homeModules.default ];
              users.alice = import ./hosts/laptop/home.nix;
            };
          }
        ];
      };
    };
}
