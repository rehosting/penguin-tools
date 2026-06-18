# Assemble the per-arch runtime closures into a dist tree, rooted under
# igloo_static/closures/ so they stay clear of the per-arch "melting pot"
# directories (igloo_static/<arch>/) that penguin globs wholesale into
# /igloo/utils:
#
#   closures/<penguinName>/closure.tar.gz   # pristine /nix/store closure
#   closures/<penguinName>/manifest.json    # { tool: "/nix/store/.../bin/tool" }
#   closures/<penguinName>/arch.txt
#   closures/<compatName> -> <penguinName>  # e.g. intel64 -> x86_64
#
# plus the musl drop-in sysroots/dylibs (dropinSysroots), merged in at
#   dylibs/<penguinName>/   sysroots/<penguinName>/
# with the same compat symlinks, for penguin's per-project init.d/*.c drop-ins.
{ pkgs, archMatrix, archClosures, dropinSysroots }:

let
  lib = pkgs.lib;
in
pkgs.runCommand "penguin-tools-dist-root"
  {
    nativeBuildInputs = with pkgs.buildPackages; [ coreutils ];
  }
  ''
    set -euo pipefail
    # Pre-create the writable parent dirs. The per-arch subtrees come from the
    # nix store at mode 0555, so we must copy *into* dirs we own rather than
    # copy the read-only parent dir itself (otherwise the next arch can't add
    # its subdir).
    mkdir -p "$out/igloo_static/closures" \
             "$out/igloo_static/dylibs" \
             "$out/igloo_static/sysroots"

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList
        (archKey: closure:
          let
            spec = archMatrix.${archKey};
            penguinArch = spec.penguinName;
            compatNames = spec.compatNames or [ ];
            sysroot = dropinSysroots.${archKey};
          in
          ''
            mkdir -p "$out/igloo_static/closures/${penguinArch}"
            cp -a ${closure}/. "$out/igloo_static/closures/${penguinArch}/"
            ${lib.concatMapStringsSep "\n"
              (compat: ''ln -sfn "${penguinArch}" "$out/igloo_static/closures/${compat}"'')
              compatNames}

            # Drop-in sysroot + dylibs (provides igloo_static/{dylibs,sysroots}/<arch>).
            cp -a ${sysroot}/igloo_static/dylibs/${penguinArch}   "$out/igloo_static/dylibs/${penguinArch}"
            cp -a ${sysroot}/igloo_static/sysroots/${penguinArch} "$out/igloo_static/sysroots/${penguinArch}"
            ${lib.concatMapStringsSep "\n"
              (compat: ''
                ln -sfn "${penguinArch}" "$out/igloo_static/dylibs/${compat}"
                ln -sfn "${penguinArch}" "$out/igloo_static/sysroots/${compat}"
              '')
              compatNames}
          '')
        archClosures
    )}

    # Some sources are read-only nix-store paths; make the assembled tree
    # writable so downstream packaging (and local edits) don't trip on 0555.
    chmod -R u+w "$out/igloo_static"
  ''
