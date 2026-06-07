{ pkgs, archBundles }:

let
  lib = pkgs.lib;
in
pkgs.runCommand "penguin-tools-dist-root"
  {
    nativeBuildInputs = with pkgs.buildPackages; [ coreutils ];
  }
  ''
    set -euo pipefail

    mkdir -p "$out/igloo_static"

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList
        (_: bundle: ''
          cp -a ${bundle}/igloo_static/. "$out/igloo_static/"
          # Bundle trees come from the read-only /nix/store, so cp -a preserves
          # their 0555 dir modes. The shared dirs (igloo_static, dylibs) must be
          # writable again before the next bundle copies its arch subdir in.
          chmod -R u+w "$out/igloo_static"
        '')
        archBundles
    )}
  ''
