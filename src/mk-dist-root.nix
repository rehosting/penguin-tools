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
        '')
        archBundles
    )}
  ''
