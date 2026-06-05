pkgs:

pkgs.gdbHostCpuOnly.overrideAttrs (prev: {
  postPatch =
    (prev.postPatch or "")
    + ''
      substituteInPlace gdb/mips-linux-nat.c \
        --replace '<sgidefs.h>' '<asm/sgidefs.h>' \
        --replace '_ABIO32' '1'
    '';

  meta.mainProgram = "gdbserver";
})
