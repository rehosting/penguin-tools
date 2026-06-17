# Produce a self-contained runtime closure for one architecture's tools.
#
# Unlike the old mk-arch-bundle.nix, this performs NO ELF rewriting, no
# interpreter/rpath patching, and no /nix/store scrubbing. It simply tars the
# pristine runtime closure of the selected tools (their real /nix/store paths)
# plus a manifest mapping each tool name to its in-store executable path.
#
# penguin extracts closure.tar.gz to the guest at /igloo/nix (giving
# /igloo/nix/store/...) and runs each tool through a wrapper that bind-mounts
# /igloo/nix onto /nix inside a private mount namespace, so the binaries' own
# absolute /nix/store paths resolve unchanged.
{ pkgs, archSpec, tools }:

let
  lib = pkgs.lib;
  penguinArch = archSpec.penguinName;
  rootDrvs = lib.mapAttrsToList (_: t: t.drv) tools;
  closure = pkgs.closureInfo { rootPaths = rootDrvs; };
  # tool name -> absolute in-store exe path (valid on the guest once /igloo/nix
  # is bind-mounted to /nix).
  manifest = builtins.toJSON (lib.mapAttrs (_: t: t.exe) tools);
in
pkgs.runCommand "penguin-closure-${penguinArch}"
  {
    nativeBuildInputs = with pkgs.buildPackages; [ gnutar gzip coreutils ];
    inherit manifest;
    passAsFile = [ "manifest" ];
  }
  ''
    set -euo pipefail
    mkdir -p "$out"

    # Tar the closure's store paths relative to / so they unpack under
    # nix/store/... (i.e. /igloo/nix/store/... after penguin extracts at /igloo).
    tar czf "$out/closure.tar.gz" \
      --sort=name --owner=0 --group=0 --numeric-owner --mtime='@1' \
      -C / $(sed 's|^/||' ${closure}/store-paths)

    cp "$manifestPath" "$out/manifest.json"
    echo "${penguinArch}" > "$out/arch.txt"
  ''
