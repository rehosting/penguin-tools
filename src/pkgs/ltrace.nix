pkgs:

let
  errorImpl = ''
    #define _GNU_SOURCE
    #include <errno.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #define error(status, errnum, ...) \
      do { \
        fflush(stdout); \
        fprintf(stderr, "ltrace: "); \
        fprintf(stderr, __VA_ARGS__); \
        if (errnum != 0) { \
          fprintf(stderr, ": %s", strerror(errnum)); \
        } \
        fprintf(stderr, "\n"); \
        if (status != 0) { \
          exit(status); \
        } \
      } while (0)
  '';
in
pkgs.ltrace.overrideAttrs (prev: {
  patches = (prev.patches or [ ]) ++ [
    (pkgs.fetchpatch {
      url = "https://raw.githubusercontent.com/openembedded/meta-openembedded/f804417cda245e073c38fbdd6749e0bd49a1c84d/meta-oe/recipes-devtools/ltrace/ltrace/0001-configure-Recognise-linux-musl-as-a-host-OS.patch";
      hash = "sha256-CoMYbe7Cf4eO8UadCEhApm5r0vwyiyjPNCbwD/H2Mxg=";
    })
  ];

  postPatch =
    (prev.postPatch or "")
    + ''
      # Add missing unistd.h so pid_t is defined on x86_64.
      printf "#include <unistd.h>\n%s" "$(cat proc.h)" > proc.h

      substituteInPlace sysdeps/linux-gnu/mips/plt.c \
        --replace 'lte->relplt_count' '//'

      substituteInPlace sysdeps/linux-gnu/{mips/plt.c,ppc/regs.c} \
        --replace '#include <error.h>' ${pkgs.lib.escapeShellArg errorImpl}

      # The ppc backend uses the kernel's PT_R0/PT_NIP/PT_LNK ptrace offsets.
      # glibc's <sys/ptrace.h> pulls these in transitively; musl's does not, so
      # include the kernel <asm/ptrace.h> that actually defines them.
      substituteInPlace sysdeps/linux-gnu/ppc/ptrace.h \
        --replace '#include <sys/ptrace.h>' '#include <sys/ptrace.h>
#include <asm/ptrace.h>'
    '';

  configureFlags = [ "--datadir=/igloo" ];
  installFlags = [ "datadir=$(out)/share" ];
  CFLAGS = "-Wno-format-overflow";
  doCheck = false;

  passthru = (prev.passthru or { }) // {
    iglooExcludedArchs = [
      "mips64eb"
      "mips64el"
      "riscv64"
      "loongarch"
    ];
    # No iglooFallbackArchs: ltrace has no 64-bit MIPS build, and symlinking the
    # 32-bit mipsel/mipseb binary does not work on a mips64 guest -- it needs the
    # 32-bit musl loader + libc, but penguin only mounts the arch's own (64-bit)
    # /igloo/dylibs, so the fallback ltrace fails to start. Treat mips64 like
    # riscv64/loongarch (no ltrace) instead of shipping a broken symlink.
  };
})
