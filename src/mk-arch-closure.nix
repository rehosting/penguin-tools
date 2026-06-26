# Produce a self-contained runtime closure for one architecture's tools.
#
# Unlike the old mk-arch-bundle.nix, this performs NO ELF rewriting, no
# interpreter/rpath patching, and no /nix/store scrubbing. It stages the
# pristine runtime closure of the selected tools (their real /nix/store paths)
# plus a manifest mapping each tool name to its in-store executable path.
#
# The one transformation it does apply is `strip`: nixpkgs' cross builds ship
# these binaries with their symbol tables intact, which is dead weight on the
# guest (~10% of the ELF bulk). We stage the closure into a writable tree and
# run the *target* arch's strip over every ELF before tarring. This only edits
# file contents, not paths -- the absolute /nix/store/... paths the binaries
# reference are unchanged, so they still resolve once penguin bind-mounts
# /igloo/nix onto /nix. (Store-path hashes no longer match the contents, but
# nothing on the guest verifies that.)
#
# penguin extracts closure.tar.gz to the guest at /igloo/nix (giving
# /igloo/nix/store/...) and runs each tool through a wrapper that bind-mounts
# /igloo/nix onto /nix inside a private mount namespace, so the binaries' own
# absolute /nix/store paths resolve unchanged.
{ pkgs, crossPkgs, archSpec, tools }:

let
  lib = pkgs.lib;
  penguinArch = archSpec.penguinName;
  rootDrvs = lib.mapAttrsToList (_: t: t.drv) tools;
  closure = pkgs.closureInfo { rootPaths = rootDrvs; };
  # tool name -> absolute in-store exe path (valid on the guest once /igloo/nix
  # is bind-mounted to /nix).
  manifest = builtins.toJSON (lib.mapAttrs (_: t: t.exe) tools);
  # The cross binutils' strip: runs on the build host, understands the target
  # arch's ELFs.
  stripCmd = "${crossPkgs.stdenv.cc.bintools.bintools}/bin/${crossPkgs.stdenv.cc.targetPrefix}strip";
in
pkgs.runCommand "penguin-closure-${penguinArch}"
  {
    nativeBuildInputs = with pkgs.buildPackages; [ gnutar gzip coreutils findutils ];
    inherit manifest;
    passAsFile = [ "manifest" ];
  }
  ''
    set -euo pipefail
    mkdir -p "$out"

    # Stage the closure's store paths into a writable tree under stage/nix/store
    # (every store path is /nix/store/<x>, so they share one parent).
    stage="$(mktemp -d)"
    mkdir -p "$stage/nix/store"
    for p in $(cat ${closure}/store-paths); do
      cp -a "$p" "$stage/nix/store/"
    done
    chmod -R u+w "$stage"

    # Strip every ELF (detected by magic bytes). strip refuses non-ELF input, so
    # the magic check keeps it quiet; failures (e.g. already-stripped) are
    # tolerated so one odd file can't fail the whole build.
    elf_magic="$(printf '\177ELF')"
    find "$stage/nix/store" -type f | while IFS= read -r f; do
      if [ "$(head -c4 "$f" 2>/dev/null)" = "$elf_magic" ]; then
        ${stripCmd} --strip-unneeded "$f" 2>/dev/null || true
      fi
    done

    # Tar the staged tree so it unpacks under nix/store/... (i.e.
    # /igloo/nix/store/... after penguin extracts at /igloo).
    tar czf "$out/closure.tar.gz" \
      --sort=name --owner=0 --group=0 --numeric-owner --mtime='@1' \
      -C "$stage" nix

    cp "$manifestPath" "$out/manifest.json"
    echo "${penguinArch}" > "$out/arch.txt"
  ''
