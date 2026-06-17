# Assemble the per-arch runtime closures into a dist tree:
#
#   <penguinName>/closure.tar.gz   # pristine /nix/store closure of the tools
#   <penguinName>/manifest.json    # { tool: "/nix/store/.../bin/tool" }
#   <penguinName>/arch.txt
#   <compatName> -> <penguinName>  # e.g. intel64 -> x86_64
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
    mkdir -p "$out/igloo_static"

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList
        (archKey: closure:
          let
            spec = archMatrix.${archKey};
            penguinArch = spec.penguinName;
            compatNames = spec.compatNames or [ ];
          in
          ''
            mkdir -p "$out/igloo_static/${penguinArch}"
            cp -a ${closure}/. "$out/igloo_static/${penguinArch}/"
            ${lib.concatMapStringsSep "\n"
              (compat: ''ln -sfn "${penguinArch}" "$out/igloo_static/${compat}"'')
              compatNames}
          '')
        archClosures
    )}
  ''
