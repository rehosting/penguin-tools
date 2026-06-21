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
#
# Guest utilities (forked, now nixified) land where penguin already expects them
# after extracting penguin-tools.tar.gz at /:
#   <penguinName>/console                 # melting-pot per-arch dir penguin globs
#   guesthopper/guesthopper.<penguinName> # resolve_arch_asset(prefix="guesthopper.")
#   guesthopper/guest_cmd.py              # host-side client, read by penguin
#   libnvram/{nvram.c,strings.c,*.h,...}  # source; penguin compiles lib_inject
# (replacing the standalone console.tar.gz / guesthopper.tar.gz downloads and
# the libnvram GitHub source pull.)
{ pkgs, archMatrix, archClosures, dropinSysroots
, consoleBins, guesthopperBins, vpnguinBins, busyboxBins, guesthopperSrc, libnvramSrc }:

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
             "$out/igloo_static/sysroots" \
             "$out/igloo_static/guesthopper" \
             "$out/igloo_static/vpn"

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList
        (archKey: closure:
          let
            spec = archMatrix.${archKey};
            penguinArch = spec.penguinName;
            compatNames = spec.compatNames or [ ];
            sysroot = dropinSysroots.${archKey};
            console = consoleBins.${archKey};
            guesthopper = guesthopperBins.${archKey};
            vpn = vpnguinBins.${archKey};
            busybox = busyboxBins.${archKey};
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

            # console + busybox -> melting-pot per-arch dir (penguin globs it into
            # /igloo/utils; gen_image also pulls busybox into /igloo/boot).
            mkdir -p "$out/igloo_static/${penguinArch}"
            cp ${console}/bin/console "$out/igloo_static/${penguinArch}/console"
            cp ${busybox}/bin/busybox "$out/igloo_static/${penguinArch}/busybox"

            # vpn (vsock_vpn): guest binary in the melting-pot dir; plus a flat
            # vpn/vpn.<arch> the host side reads (vpn.py uses vpn/vpn.x86_64).
            cp ${vpn}/bin/vsock_vpn "$out/igloo_static/${penguinArch}/vpn"
            ln -sfn "../${penguinArch}/vpn" "$out/igloo_static/vpn/vpn.${penguinArch}"
            ${lib.concatMapStringsSep "\n"
              (compat: ''ln -sfn "../${penguinArch}/vpn" "$out/igloo_static/vpn/vpn.${compat}"'')
              compatNames}

            # guesthopper.<arch>; canonical name + compat aliases for resolve_arch_asset.
            cp ${guesthopper}/bin/guesthopper "$out/igloo_static/guesthopper/guesthopper.${penguinArch}"
            ${lib.concatMapStringsSep "\n"
              (compat: ''ln -sfn "guesthopper.${penguinArch}" "$out/igloo_static/guesthopper/guesthopper.${compat}"'')
              compatNames}
          '')
        archClosures
    )}

    # guesthopper host-side client (arch-independent), read by penguin at
    # /igloo_static/guesthopper/guest_cmd.py.
    cp ${guesthopperSrc}/guest_cmd.py "$out/igloo_static/guesthopper/guest_cmd.py"

    # libnvram source tree (arch-independent). penguin globs
    # /igloo_static/libnvram/*.{c,h} to compile lib_inject per project, so ship
    # the .c/.h set (nvram.c #includes nvram.h, config.h, portalcall.h,
    # strings.h, strings.c). No prebuilt .so -- it's unused (lib_inject replaces
    # the old LD_PRELOAD'd libnvram.so).
    mkdir -p "$out/igloo_static/libnvram"
    cp ${libnvramSrc}/*.c ${libnvramSrc}/*.h "$out/igloo_static/libnvram/"

    # Some sources are read-only nix-store paths; make the assembled tree
    # writable so downstream packaging (and local edits) don't trip on 0555.
    chmod -R u+w "$out/igloo_static"
  ''
