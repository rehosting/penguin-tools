# Per-arch build matrix.
#
# crossSystem      -- glibc cross system used to build the pristine runtime
#                     closures of the debugging tools (python3/strace/gdbserver/
#                     ltrace). glibc because there is no static linking, so the
#                     musl-only overrides that used to be needed are gone.
# muslCrossSystem  -- musl cross system used ONLY to stage the drop-in
#                     compilation sysroot + dylibs (crt objects, musl loader,
#                     libc.so, libgcc_s.so.1) that penguin links per-project
#                     init.d/*.c drop-ins against. Kept on musl for runtime
#                     consistency with how drop-ins have always been built.
{
  x86_64 = {
    penguinName = "x86_64";
    compatNames = [ "intel64" ];
    crossSystem = {
      config = "x86_64-unknown-linux-gnu";
      # x86_64's cross target shares its config string with the x86_64-linux
      # build host -- a degenerate (same-system) cross. nixpkgs decides "are we
      # cross compiling?" inconsistently in that case: some paths compare only
      # localSystem vs crossSystem (=> "native"), others also honour
      # crossOverlays (=> "cross"). We pass a non-empty crossOverlays on every
      # arch (the glibc vDSO gate in flake.nix), so the two disagree and the
      # glibc fixpoint recurses. Adding any extra field makes the elaborated
      # crossSystem differ from localSystem, so every check agrees on "cross"
      # and the recursion goes away. See NixOS/nixpkgs#265121.
      dummyValueToForceCrossCompiling = true;
    };
    muslCrossSystem = {
      config = "x86_64-linux-musl";
    };
  };

  armel = {
    penguinName = "armel";
    crossSystem = {
      config = "armv7l-unknown-linux-gnueabihf";
    };
    muslCrossSystem = {
      config = "armv7l-linux-musleabi";
    };
  };

  arm64 = {
    penguinName = "aarch64";
    crossSystem = {
      config = "aarch64-unknown-linux-gnu";
    };
    muslCrossSystem = {
      config = "aarch64-linux-musl";
    };
  };

  mipsel = {
    penguinName = "mipsel";
    crossSystem = {
      config = "mipsel-unknown-linux-gnu";
      gcc.arch = "mips32r2";
    };
    muslCrossSystem = {
      config = "mipsel-linux-musl";
      gcc.arch = "mips32r2";
    };
  };

  mipseb = {
    penguinName = "mipseb";
    crossSystem = {
      config = "mips-unknown-linux-gnu";
      gcc.arch = "mips32r2";
    };
    muslCrossSystem = {
      config = "mips-linux-musl";
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
    muslCrossSystem = {
      config = "mips64el-linux-musl";
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
    muslCrossSystem = {
      config = "mips64-linux-musl";
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
    muslCrossSystem = {
      config = "powerpc64-linux-musl";
      gcc.abi = "elfv2";
    };
  };

  ppc64el = {
    penguinName = "powerpc64le";
    compatNames = [ "powerpc64el" ];
    crossSystem = {
      config = "powerpc64le-unknown-linux-gnu";
    };
    muslCrossSystem = {
      config = "powerpc64le-linux-musl";
    };
  };

  riscv64 = {
    penguinName = "riscv64";
    crossSystem = {
      config = "riscv64-unknown-linux-gnu";
    };
    muslCrossSystem = {
      config = "riscv64-linux-musl";
    };
  };

  loongarch = {
    penguinName = "loongarch64";
    crossSystem = {
      config = "loongarch64-unknown-linux-gnu";
    };
    muslCrossSystem = {
      config = "loongarch64-linux-musl";
    };
  };
}
