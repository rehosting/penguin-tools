# Build a small, self-contained C guest utility (e.g. console) as a static
# binary cross-compiled for one target arch.
#
# These tools have no runtime closure -- they are statically linked against
# musl and drop into the guest as a single file -- so unlike the debugging
# tools (mk-arch-closure.nix) there is nothing to bind-mount; the output is
# just $out/bin/<outName>.
#
#   crossPkgs  -- a musl cross nixpkgs (archs.nix muslCrossSystem) so the binary
#                 is fully static and freestanding in the guest.
#   src        -- the (forked) source tree of the utility.
#   pname      -- derivation name.
#   sources    -- list of .c files to compile (relative to src).
#   outName    -- installed binary name (what penguin expects in the tarball).
#   defines    -- attrset of -D macros (string values are quoted for C).
#   extraCFlags-- arch-specific flags (e.g. [ "-mips32r3" ]).
{ crossPkgs
, src
, pname
, sources ? [ ]
, outName
, defines ? { }
, extraCFlags ? [ ]
}:

let
  lib = crossPkgs.lib;
  # Single-quote the value so bash preserves the inner double quotes and the
  # compiler sees a C string literal (-DSERIAL='"/igloo/serial"'), matching
  # console's Makefile (-DSERIAL=\"/igloo/serial\").
  defineFlags =
    lib.mapAttrsToList (k: v: "-D${k}='\"${toString v}\"'") defines;
  cflags = lib.concatStringsSep " " ([ "-static" "-O2" "-Wall" ] ++ extraCFlags ++ defineFlags);
in
crossPkgs.stdenv.mkDerivation {
  inherit pname src;
  version = "0";

  dontConfigure = true;

  # Use the cross stdenv's $CC directly rather than the upstream Makefile: the
  # Makefile keys its per-arch flags off bespoke triple names (mipsel-linux-musl
  # etc.) that don't match nixpkgs' config strings, and nix already selects the
  # correct cross-gcc. The flags here mirror console's Makefile verbatim.
  buildPhase = ''
    runHook preBuild
    $CC ${cflags} ${lib.concatStringsSep " " sources} -o ${outName}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ${outName} "$out/bin/${outName}"
    runHook postInstall
  '';

  # Static musl binaries have no dynamic deps; skip the (cross-hostile) checks.
  dontStrip = true;
  dontPatchELF = true;
}
