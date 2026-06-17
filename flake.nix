{
  description = "Penguin guest tools builder";

  nixConfig = {
    extra-substituters = [ "https://rehosting-tools.cachix.org" ];
    extra-trusted-public-keys = [
      "rehosting-tools.cachix.org-1:iNKSaFwG7MfGn6Fk7oTmIcLHqfffQ+cQIE5gWc6MlY0="
    ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/b6067cc0127d4db9c26c79e4de0513e58d0c40c9";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      archMatrix = import ./src/archs.nix;

      # Pristine nixpkgs for the build host. No overlays: the tools are shipped
      # as their unmodified upstream runtime closures (see mk-arch-closure.nix).
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnsupportedSystem = true;
      };
      lib = pkgs.lib;

      # Generic cross-compilation fixes (e.g. gnutls' target-binary doc build).
      crossOverlays = import ./src/cross-overlays.nix;

      mkCrossPkgs = archKey:
        import nixpkgs {
          inherit system;
          config.allowUnsupportedSystem = true;
          overlays = crossOverlays;
          crossSystem = archMatrix.${archKey}.crossSystem;
        };

      # musl cross pkgs, used only to stage the drop-in compilation sysroot.
      mkMuslCrossPkgs = archKey:
        import nixpkgs {
          inherit system;
          config.allowUnsupportedSystem = true;
          crossSystem = archMatrix.${archKey}.muslCrossSystem;
        };

      # ltrace has no working build on these targets (no 64-bit MIPS / RISC-V /
      # LoongArch backend). Everything else ships python3, strace, gdbserver.
      ltraceUnsupported = [ "mips64eb" "mips64el" "riscv64" "loongarch" ];

      mkTools = archKey: crossPkgs:
        let
          base = {
            python3 = {
              drv = crossPkgs.python3;
              exe = "${crossPkgs.python3}/bin/python3";
            };
            strace = {
              drv = crossPkgs.strace;
              exe = "${crossPkgs.strace}/bin/strace";
            };
            # debuginfod is a gdb *client* feature (symbol fetching over HTTP);
            # a guest gdbserver never uses it. Disabling it drops the heavy and
            # cross-hostile elfutils -> libmicrohttpd -> gnutls chain (gnutls'
            # doc build runs target binaries and fails under cross-compilation),
            # and shrinks the shipped closure.
            gdbserver =
              let gdb = crossPkgs.gdbHostCpuOnly.override { enableDebuginfod = false; };
              in {
                drv = gdb;
                exe = "${gdb}/bin/gdbserver";
              };
            # iptables is a single multi-call package (xtables-*-multi) that
            # dispatches on argv[0]; one derivation provides both the nft and
            # legacy entry points, so ship both exes from the same closure.
            iptables = {
              drv = crossPkgs.iptables;
              exe = "${crossPkgs.iptables}/bin/iptables";
            };
            iptables-legacy = {
              drv = crossPkgs.iptables;
              exe = "${crossPkgs.iptables}/bin/iptables-legacy";
            };
          };
          ltrace = {
            ltrace = {
              drv = crossPkgs.ltrace;
              exe = "${crossPkgs.ltrace}/bin/ltrace";
            };
          };
        in
        base // (if builtins.elem archKey ltraceUnsupported then { } else ltrace);

      mkArchClosure = archKey:
        import ./src/mk-arch-closure.nix {
          inherit pkgs;
          archSpec = archMatrix.${archKey};
          tools = mkTools archKey (mkCrossPkgs archKey);
        };

      archClosures = lib.mapAttrs (archKey: _: mkArchClosure archKey) archMatrix;

      mkDropinSysroot = archKey:
        import ./src/mk-dropin-sysroot.nix {
          inherit pkgs;
          archSpec = archMatrix.${archKey};
          muslCrossPkgs = mkMuslCrossPkgs archKey;
        };

      dropinSysroots = lib.mapAttrs (archKey: _: mkDropinSysroot archKey) archMatrix;

      distRoot = import ./src/mk-dist-root.nix {
        inherit pkgs archMatrix archClosures dropinSysroots;
      };

      dist = import ./src/mk-dist-tarball.nix {
        inherit pkgs distRoot;
      };

      # Per-arch closures / sysroots exposed individually for partial builds.
      closurePackages = builtins.listToAttrs (
        lib.mapAttrsToList
          (archKey: closure: {
            name = "closure-${archMatrix.${archKey}.penguinName}";
            value = closure;
          })
          archClosures
      );
      sysrootPackages = builtins.listToAttrs (
        lib.mapAttrsToList
          (archKey: sysroot: {
            name = "sysroot-${archMatrix.${archKey}.penguinName}";
            value = sysroot;
          })
          dropinSysroots
      );
    in
    {
      packages.${system} =
        closurePackages
        // sysrootPackages
        // {
          "dist-root" = distRoot;
          dist = dist;
          default = dist;
        };

      checks.${system} = {
        dist = dist;
      };
    };
}
