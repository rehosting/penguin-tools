# Build the forked busybox as a static-musl binary for one target arch, using
# the checked-in .config (CONFIG_STATIC=y) verbatim.
#
# The fork's instrumentation headers (include/hypercall_logging.h) pull in
# include/portalcall.h -> include/libhc/hypercall.h, which is a git submodule
# (panda-re/libhc). We provide it from the `libhc` source input rather than
# initialising a submodule.
#
#   crossPkgs -- a musl cross nixpkgs (archs.nix muslCrossSystem) for a fully
#                static guest binary; its stdenv.cc.targetPrefix drives kbuild's
#                CROSS_COMPILE, matching how nixpkgs builds busybox/linux cross.
#   src       -- the forked busybox source tree (with .config).
#   libhc     -- the libhc source tree (provides hypercall.h).
{ crossPkgs, src, libhc }:

crossPkgs.stdenv.mkDerivation {
  pname = "busybox";
  version = "0";
  inherit src;

  # Use the checked-in .config; don't run a configure step.
  dontConfigure = true;

  postPatch = ''
    # Supply the libhc submodule the fork's headers include.
    mkdir -p include/libhc
    cp ${libhc}/hypercall.h include/libhc/hypercall.h
  '';

  # CROSS_COMPILE selects the cross toolchain (kbuild builds $(CROSS_COMPILE)gcc
  # etc.); HOSTCC builds the config/host helpers with the native compiler. Don't
  # pass the fork's -mips32r3 etc.: archs.nix already pins gcc.arch per arch, and
  # an extra -march conflicts (same lesson as console).
  buildPhase = ''
    runHook preBuild
    make -j"$NIX_BUILD_CORES" \
      CROSS_COMPILE="${crossPkgs.stdenv.cc.targetPrefix}" \
      HOSTCC="${crossPkgs.buildPackages.stdenv.cc}/bin/cc" \
      SKIP_STRIP=y \
      busybox
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 busybox "$out/bin/busybox"
    runHook postInstall
  '';

  dontStrip = true;
  dontPatchELF = true;
}
