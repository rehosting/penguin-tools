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
            # gdb pinned to 16.3 rather than nixpkgs' 17.1: 17.1 does not
            # cross-build across our arch set (aarch64 struct user_gcs
            # redefinition vs modern kernel headers, ser-unix.c custom-baudrate
            # termios fields, and gdbserver's in-process agent erroring out on
            # armv7l). 16.3 is what Alpine/Buildroot ship and predates all of
            # that. Plus: disable the (unused, not-everywhere-supported)
            # in-process agent, fix the mips sgidefs include, and disable
            # debuginfod -- a gdb *client* feature a guest gdbserver never uses,
            # which also drops the heavy elfutils -> libmicrohttpd -> gnutls
            # chain and shrinks the closure.
            gdbserver =
              let
                gdb = (crossPkgs.gdbHostCpuOnly.override { enableDebuginfod = false; }).overrideAttrs (prev: {
                  version = "16.3";
                  src = crossPkgs.fetchurl {
                    url = "mirror://gnu/gdb/gdb-16.3.tar.xz";
                    hash = "sha256-vPzQlVKKmHkXrPn/8/FnIYFpSSbMGNYJyZ0AQsACJMU=";
                  };
                  postPatch = (prev.postPatch or "") + ''
                    substituteInPlace gdb/mips-linux-nat.c \
                      --replace '<sgidefs.h>' '<asm/sgidefs.h>' \
                      --replace '_ABIO32' '1'
                  '';
                  configureFlags = (prev.configureFlags or [ ]) ++ [ "--disable-inprocess-agent" ];
                  meta = (prev.meta or { }) // { mainProgram = "gdbserver"; };
                });
              in
              {
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
          # ltrace needs a couple of cross fixes: its mips backend references a
          # struct member (relplt_count) that doesn't exist here, and proc.h
          # uses pid_t without including unistd.h. Also point its prototype
          # datadir at /igloo (where penguin stages the ltrace .conf files).
          ltraceDrv = crossPkgs.ltrace.overrideAttrs (prev: {
            postPatch = (prev.postPatch or "") + ''
              printf "#include <unistd.h>\n%s" "$(cat proc.h)" > proc.h
              substituteInPlace sysdeps/linux-gnu/mips/plt.c \
                --replace 'lte->relplt_count' '//'
            '';
            configureFlags = (prev.configureFlags or [ ]) ++ [ "--datadir=/igloo" ];
            installFlags = (prev.installFlags or [ ]) ++ [ "datadir=$(out)/share" ];
            CFLAGS = "-Wno-format-overflow";
            doCheck = false;
          });
          ltrace = {
            ltrace = {
              drv = ltraceDrv;
              exe = "${ltraceDrv}/bin/ltrace";
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
