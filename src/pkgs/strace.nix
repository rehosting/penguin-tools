pkgs:

(pkgs.strace.override { libunwind = null; }).overrideAttrs (_: {
  passthru.iglooExcludedArchs = [ "riscv32" ];
})
