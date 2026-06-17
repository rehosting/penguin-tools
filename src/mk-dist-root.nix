# Assemble the per-arch runtime closures into a dist tree, rooted under
# igloo_static/closures/ so they stay clear of the per-arch "melting pot"
# directories (igloo_static/<arch>/) that penguin globs wholesale into
# /igloo/utils:
#
#   closures/<penguinName>/closure.tar.gz   # pristine /nix/store closure
#   closures/<penguinName>/manifest.json    # { tool: "/nix/store/.../bin/tool" }
#   closures/<penguinName>/arch.txt
#   closures/<compatName> -> <penguinName>  # e.g. intel64 -> x86_64
{ pkgs, archMatrix, archClosures }:

let
  lib = pkgs.lib;
in
pkgs.runCommand "penguin-tools-dist-root"
  {
    nativeBuildInputs = with pkgs.buildPackages; [ coreutils ];
  }
  ''
    set -euo pipefail
    mkdir -p "$out/igloo_static/closures"

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList
        (archKey: closure:
          let
            spec = archMatrix.${archKey};
            penguinArch = spec.penguinName;
            compatNames = spec.compatNames or [ ];
          in
          ''
            mkdir -p "$out/igloo_static/closures/${penguinArch}"
            cp -a ${closure}/. "$out/igloo_static/closures/${penguinArch}/"
            ${lib.concatMapStringsSep "\n"
              (compat: ''ln -sfn "${penguinArch}" "$out/igloo_static/closures/${compat}"'')
              compatNames}
          '')
        archClosures
    )}
  ''
