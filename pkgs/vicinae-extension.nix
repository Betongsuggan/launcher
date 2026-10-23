# An extension of the vicinaehq/extensions repository, built on its own (the
# same build Home Manager's `config.lib.vicinae.mkExtension` does, inlined so
# it works outside a Home Manager evaluation). Its provider id in
# `vicinae://launch/<id>/<command>` is `@<author>/<name>` from its
# package.json (`vicinae cmd ls` lists them).
{
  buildNpmPackage,
  importNpmLock,
  src,
}:
name:
let
  # Fixes that have not landed upstream. Each is made against the pinned
  # input, so bumping the input past the lines they touch fails the build
  # instead of silently dropping the fix.
  patches = {
    # Open networks: nmcli's table prints "--" for an empty SECURITY column,
    # which the extension took for a secured network and asked a password for
    wifi-commander = [ ../patches/wifi-commander-open-networks.patch ];
  };
  extensionSrc = "${src}/extensions/${name}";
in
buildNpmPackage {
  inherit name;
  src = extensionSrc;
  npmDeps = importNpmLock { npmRoot = extensionSrc; };
  inherit (importNpmLock) npmConfigHook;

  patches = patches.${name} or [ ];

  # Extensions extend the repository root's tsconfig; built out of tree they
  # lose it and the bundler falls back to classic JSX (a bare `React` global
  # vicinae doesn't provide). Point it at the root's.
  postPatch = ''
    substituteInPlace tsconfig.json --replace-quiet \
      '"../../tsconfig.json"' '"${src}/tsconfig.json"'
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r /build/.local/share/vicinae/extensions/${name}/* $out/
    runHook postInstall
  '';
}
