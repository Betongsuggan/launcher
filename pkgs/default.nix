# Packages built against the consumer's nixpkgs (`pkgs`), from the sources
# pinned by this flake's inputs. Overlay-free on purpose: with Home Manager's
# useGlobalPkgs a module cannot add overlays, and `callPackage` keeps one
# nixpkgs, honouring the consumer's overlays and config.
{ pkgs, inputs }:
{
  audiomenu = pkgs.callPackage "${inputs.audiomenu}/package.nix" { };
  monitormenu = pkgs.callPackage "${inputs.monitormenu}/package.nix" { };
  # name -> the extension from the pinned vicinaehq/extensions, patched
  vicinae-extension = pkgs.callPackage ./vicinae-extension.nix { src = inputs.vicinae-extensions; };
}
