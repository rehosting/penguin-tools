{
  x86_64 = {
    penguinName = "x86_64";
    compatNames = [ "intel64" ];
    crossSystem = {
      config = "x86_64-unknown-linux-gnu";
    };
  };

  armel = {
    penguinName = "armel";
    crossSystem = {
      config = "armv7l-unknown-linux-gnueabihf";
    };
  };

  arm64 = {
    penguinName = "aarch64";
    crossSystem = {
      config = "aarch64-unknown-linux-gnu";
    };
  };

  mipsel = {
    penguinName = "mipsel";
    crossSystem = {
      config = "mipsel-unknown-linux-gnu";
      gcc.arch = "mips32r2";
    };
  };

  mipseb = {
    penguinName = "mipseb";
    crossSystem = {
      config = "mips-unknown-linux-gnu";
      gcc.arch = "mips32r2";
    };
  };

  mips64el = {
    penguinName = "mips64el";
    crossSystem = {
      config = "mips64el-unknown-linux-gnuabi64";
      gcc.arch = "mips64r2";
      gcc.abi = "64";
    };
  };

  mips64eb = {
    penguinName = "mips64eb";
    crossSystem = {
      config = "mips64-unknown-linux-gnuabi64";
      gcc.arch = "mips64r2";
      gcc.abi = "64";
    };
  };

  ppc64 = {
    penguinName = "powerpc64";
    crossSystem = {
      config = "powerpc64-unknown-linux-gnuabielfv2";
      gcc.abi = "elfv2";
    };
  };

  ppc64el = {
    penguinName = "powerpc64le";
    compatNames = [ "powerpc64el" ];
    crossSystem = {
      config = "powerpc64le-unknown-linux-gnu";
    };
  };

  riscv64 = {
    penguinName = "riscv64";
    crossSystem = {
      config = "riscv64-unknown-linux-gnu";
    };
  };

  loongarch = {
    penguinName = "loongarch64";
    crossSystem = {
      config = "loongarch64-unknown-linux-gnu";
    };
  };
}
