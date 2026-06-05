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

  ppc = {
    penguinName = "powerpc";
    compatNames = [ "powerpcle" ];
    crossSystem = {
      config = "powerpc-linux-musl";
    };
  };

  ppc64 = {
    penguinName = "powerpc64";
    crossSystem = {
      config = "powerpc64-linux-musl";
      gcc.abi = "elfv2";
    };
  };

  ppc64el = {
    penguinName = "powerpc64le";
    compatNames = [ "powerpc64el" ];
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
    crossSystem = {
      config = "loongarch64-linux-musl";
    };
  };
}
