pkgs:

# gdb is pinned to 16.3 rather than tracking nixpkgs' latest: 16.3 is the
# version Alpine/Buildroot ship on musl across our arch set, and it predates
# the gdb-17 GCS (struct user_gcs) and custom-baudrate (termios c_ispeed) code
# that does not compile against musl + modern kernel headers. Stable over new.
pkgs.gdbHostCpuOnly.overrideAttrs (prev: {
  version = "16.3";
  src = pkgs.fetchurl {
    url = "mirror://gnu/gdb/gdb-16.3.tar.xz";
    hash = "sha256-vPzQlVKKmHkXrPn/8/FnIYFpSSbMGNYJyZ0AQsACJMU=";
  };

  postPatch =
    (prev.postPatch or "")
    + ''
      substituteInPlace gdb/mips-linux-nat.c \
        --replace '<sgidefs.h>' '<asm/sgidefs.h>' \
        --replace '_ABIO32' '1'
    '';

  # gdbserver's in-process agent (fast tracepoints) is not supported on every
  # target and its configure makes that a hard error (e.g. armv7l-musl). We
  # don't use the IPA, so disable it everywhere.
  configureFlags = (prev.configureFlags or [ ]) ++ [ "--disable-inprocess-agent" ];

  meta.mainProgram = "gdbserver";
})
