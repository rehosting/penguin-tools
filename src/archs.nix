{
  x86_64 = {
    penguinName = "x86_64";
    compatNames = [ "intel64" ];
    crossSystem = {
      config = "x86_64-linux-musl";
    };
  };

  armel = {
    penguinName = "armel";
    crossSystem = {
      config = "armv7l-linux-musleabi";
    };
  };

  arm64 = {
    penguinName = "aarch64";
    # "arm64" is the legacy dylib/arch dir name the rest of penguin still uses.
    compatNames = [ "arm64" ];
    crossSystem = {
      config = "aarch64-linux-musl";
    };
  };

  mipsel = {
    penguinName = "mipsel";
    crossSystem = {
      config = "mipsel-linux-musl";
      gcc.arch = "mips32r2";
    };
  };

  mipseb = {
    penguinName = "mipseb";
    crossSystem = {
      config = "mips-linux-musl";
      gcc.arch = "mips32r2";
    };
  };

  mips64el = {
    penguinName = "mips64el";
    crossSystem = {
      config = "mips64el-linux-musl";
      gcc.arch = "mips64r2";
      gcc.abi = "64";
    };
  };

  mips64eb = {
    penguinName = "mips64eb";
    crossSystem = {
      config = "mips64-linux-musl";
      gcc.arch = "mips64r2";
      gcc.abi = "64";
    };
  };

  ppc64 = {
    penguinName = "powerpc64";
    # "ppc64" is the legacy dylib/arch dir name the rest of penguin still uses.
    compatNames = [ "ppc64" ];
    crossSystem = {
      config = "powerpc64-linux-musl";
      gcc.abi = "elfv2";
    };
  };

  ppc64el = {
    penguinName = "powerpc64le";
    # "ppc64el" is the legacy dylib/arch dir name the rest of penguin uses.
    compatNames = [ "powerpc64el" "ppc64el" ];
    crossSystem = {
      config = "powerpc64le-linux-musl";
    };
  };

  riscv64 = {
    penguinName = "riscv64";
    crossSystem = {
      config = "riscv64-linux-musl";
    };
  };

  loongarch = {
    penguinName = "loongarch64";
    # "loongarch" is the legacy dylib/arch dir name the rest of penguin uses.
    compatNames = [ "loongarch" ];
    crossSystem = {
      config = "loongarch64-linux-musl";
    };
  };
}
