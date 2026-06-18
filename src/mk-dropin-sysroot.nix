# Stage the musl drop-in compilation sysroot + dylibs for one architecture.
#
# This is NOT the old mk-arch-bundle.nix: it does NO ELF rewriting, no rpath
# patching and no /nix/store scrubbing. It copies a small, pristine subset of a
# musl cross toolchain that penguin needs to compile and run per-project
# init.d/*.c drop-ins:
#
#   igloo_static/dylibs/<arch>/
#       libc.so                 # musl libc (also the dynamic loader)
#       ld-musl-<arch>.so.1      # -> libc.so  (the drop-in's PT_INTERP)
#       libgcc_s.so.1            # gcc runtime
#   igloo_static/sysroots/<arch>/lib/
#       Scrt1.o crti.o crtn.o crtbeginS.o crtendS.o   # link-time crt objects
#       libc.so       -> ../../../dylibs/<arch>/libc.so
#       libgcc_s.so.1 -> ../../../dylibs/<arch>/libgcc_s.so.1
#
# penguin's dropin_compile.py links drop-ins with
#   --dynamic-linker /igloo/dylibs/ld-musl-<arch>.so.1  -rpath /igloo/dylibs
# so the loader and these runtime libs resolve at /igloo/dylibs on the guest.
# The Dockerfile layers musl headers and the libgcc_s.so linker alias on top.
{ pkgs, archSpec, muslCrossPkgs }:

let
  lib = pkgs.lib;
  arch = archSpec.penguinName;
  musl = muslCrossPkgs.musl;
  cc = muslCrossPkgs.stdenv.cc;
  ccCmd = "${cc.targetPrefix}cc";
in
pkgs.runCommand "penguin-dropin-sysroot-${arch}"
  {
    nativeBuildInputs = (with pkgs.buildPackages; [ coreutils findutils ]) ++ [ cc ];
  }
  ''
    set -euo pipefail

    dylib_dir="$out/igloo_static/dylibs/${arch}"
    sysroot_lib="$out/igloo_static/sysroots/${arch}/lib"
    mkdir -p "$dylib_dir" "$sysroot_lib"

    # musl libc / loader (a single file in musl) -- left ELF-intact: patching the
    # loader's layout corrupts its BSS and segfaults every dynamic binary.
    cp -L "${musl}/lib/libc.so" "$dylib_dir/libc.so"
    chmod u+w "$dylib_dir/libc.so"

    # Expose the loader under its canonical ld-musl-<arch>.so.1 name.
    loader="$(cd "${musl}/lib" && ls ld-musl-*.so.1 | head -n1)"
    if [ -z "$loader" ]; then
      echo "could not find musl loader (ld-musl-*.so.1) for ${arch}" >&2
      exit 1
    fi
    ln -sfn libc.so "$dylib_dir/$loader"

    # gcc runtime lib, resolved through the cross cc wrapper.
    libgcc="$(${ccCmd} -print-file-name=libgcc_s.so.1)"
    if [ ! -e "$libgcc" ]; then
      echo "could not resolve libgcc_s.so.1 for ${arch} (got: $libgcc)" >&2
      exit 1
    fi
    cp -L "$libgcc" "$dylib_dir/libgcc_s.so.1"
    chmod u+w "$dylib_dir/libgcc_s.so.1"

    # crt startup objects for linking drop-ins, from this arch's own toolchain.
    for obj in Scrt1.o crti.o crtn.o crtbeginS.o crtendS.o; do
      src="$(${ccCmd} -print-file-name=$obj)"
      if [ ! -e "$src" ]; then
        echo "could not resolve crt object $obj for ${arch} (got: $src)" >&2
        exit 1
      fi
      cp "$src" "$sysroot_lib/$obj"
      chmod u+w "$sysroot_lib/$obj"
    done

    # libc/libgcc in the sysroot come from the matching dylibs dir.
    ln -sfn "../../../dylibs/${arch}/libc.so" "$sysroot_lib/libc.so"
    ln -sfn "../../../dylibs/${arch}/libgcc_s.so.1" "$sysroot_lib/libgcc_s.so.1"
  ''
