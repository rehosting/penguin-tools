pkgs:

pkgs.gdbHostCpuOnly.overrideAttrs (prev: {
  postPatch =
    (prev.postPatch or "")
    + ''
      substituteInPlace gdb/mips-linux-nat.c \
        --replace '<sgidefs.h>' '<asm/sgidefs.h>' \
        --replace '_ABIO32' '1'

      # gdb only skips its own "struct user_gcs" definition when GCS_MAGIC is
      # defined, but recent aarch64 kernel headers (>=6.13) put user_gcs in
      # <asm/ptrace.h> while GCS_MAGIC lives in <asm/sigcontext.h> (which
      # ptrace.h does not include), so the guard never fires and the struct is
      # redefined. Key the guard off ptrace.h's own include guard instead: the
      # files that include <asm/ptrace.h> get the kernel's struct, and the one
      # that doesn't (aarch64-linux-tdep.c) keeps gdb's fallback definition.
      substituteInPlace gdb/arch/aarch64-gcs-linux.h \
        --replace '#ifndef GCS_MAGIC' '#ifndef __ASM_PTRACE_H'

      # gdb's Linux custom-baudrate path uses struct termios2 when TCGETS2 is
      # defined, otherwise plain struct termios with .c_ispeed/.c_ospeed. musl
      # never defines TCGETS2, so the fallback is taken, but musl names those
      # fields __c_ispeed/__c_ospeed. All our targets are musl, so map the two
      # field accesses to the musl names.
      substituteInPlace gdb/ser-unix.c \
        --replace 'tio.c_ospeed = rate;' 'tio.__c_ospeed = rate;' \
        --replace 'tio.c_ispeed = rate;' 'tio.__c_ispeed = rate;'
    '';

  meta.mainProgram = "gdbserver";
})
