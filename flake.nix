{
  description = "Penguin guest tools builder";

  nixConfig = {
    extra-substituters = [ "https://rehosting-tools.cachix.org" ];
    extra-trusted-public-keys = [
      "rehosting-tools.cachix.org-1:iNKSaFwG7MfGn6Fk7oTmIcLHqfffQ+cQIE5gWc6MlY0="
    ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/b6067cc0127d4db9c26c79e4de0513e58d0c40c9";

  # Forked guest utilities, consumed as plain source trees (no flake of their
  # own). SPIKE: console only for now, to prove the cross-build pattern.
  inputs.console = {
    url = "github:rehosting/console/e84247c974198c0d793f0dd687d6c469881c31c9";
    flake = false;
  };
  inputs.guesthopper = {
    url = "github:rehosting/guesthopper/accd54780869e68e5242fc1fd5e972d2071f680b";
    flake = false;
  };
  # libnvram needs no cross-compile: penguin compiles nvram.c -> lib_inject.so
  # itself (clang-20, per project). We just vendor its source tree, replacing
  # the standalone GitHub source pull in penguin's Dockerfile.
  inputs.libnvram = {
    url = "github:rehosting/libnvram/e013c0686facbb62df09b30d0d5b92dd75fd4d58";
    flake = false;
  };
  inputs.vpnguin = {
    url = "github:rehosting/vpnguin/07f6de9bad32fbfb74c26ac0f80e3d5f3caf336b";
    flake = false;
  };
  inputs.busybox = {
    url = "github:rehosting/busybox/4d3876723484b2a558b7b0179bb40c7d9e184982";
    flake = false;
  };
  # libhc: hypercall.h header the busybox fork includes (its submodule).
  inputs.libhc = {
    url = "github:panda-re/libhc/b2f2efbd948faca9e242ae410e035c0065ec433a";
    flake = false;
  };

  outputs = { self, nixpkgs, console, guesthopper, libnvram, vpnguin, busybox, libhc }:
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
          # python3 trimmed for the guest: drop the static-lib/build "config"
          # dir (~40M of libpython.a + Makefiles, only needed to compile C
          # extensions *against* python, which the guest never does), the IDLE
          # GUI, the stdlib test suite, and tkinter. Pure size; the interpreter
          # and stdlib the guest actually runs are untouched.
          slimPython = crossPkgs.python3.override {
            stripConfig = true;
            stripIdlelib = true;
            stripTests = true;
            stripTkinter = true;
          };
          base = {
            python3 = {
              drv = slimPython;
              exe = "${slimPython}/bin/python3";
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
            #
            # Also drop source-highlight (gdb's nixpkgs expr links it
            # unconditionally, no flag): it is the gdb client's source syntax
            # coloring, which gdbserver never uses, and it is the *sole* path by
            # which boost (~15M) and icu4c (~39M) enter the closure. Filtering
            # it out of buildInputs makes gdb's configure auto-disable it and
            # removes ~57M/arch of dead weight.
            #
            # And disable pythonSupport: it is gdb-client scripting only, and it
            # drags in the *full* (unstripped) python3 -- defeating slimPython
            # above by shipping a second 114M python in the closure. gdbserver
            # needs no python, so turning it off leaves only slimPython.
            gdbserver =
              let
                gdb = (crossPkgs.gdbHostCpuOnly.override { enableDebuginfod = false; pythonSupport = false; }).overrideAttrs (prev: {
                  buildInputs = lib.filter
                    (p: !(lib.hasInfix "source-highlight" (p.name or "")))
                    (prev.buildInputs or [ ]);
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

      # --- Guest C utilities (SPIKE: console) -------------------------------
      # Built as static-musl binaries via muslCrossSystem. console's Makefile
      # hardcodes -march on MIPS, but archs.nix already pins gcc.arch per arch
      # (mips32r2/mips64r2), matching the debugging-tool closures, so we let the
      # cross stdenv set -march rather than fighting it with an extra flag.
      mkConsole = archKey:
        import ./src/mk-guest-c-tool.nix {
          crossPkgs = mkMuslCrossPkgs archKey;
          src = console;
          pname = "console-${archMatrix.${archKey}.penguinName}";
          sources = [ "console.c" ];
          outName = "console";
          defines = {
            SHELL = "/igloo/utils/sh";
            SERIAL = "/igloo/serial";
          };
        };
      # archKey-keyed for dist assembly; *Packages (below) are the named outputs.
      consoleBins = lib.mapAttrs (archKey: _: mkConsole archKey) archMatrix;
      consolePackages = builtins.listToAttrs (
        lib.mapAttrsToList
          (archKey: _: {
            name = "console-${archMatrix.${archKey}.penguinName}";
            value = consoleBins.${archKey};
          })
          archMatrix
      );

      # --- Guest Rust utilities --------------------------------------------
      # rust has no usable mips64 musl target (n64 muslabi64 is tier-3, no std),
      # so -- like the upstream Docker builds, which copy the 32-bit mips binary
      # to the mips64 slot -- the mips64 guests reuse the 32-bit mips Rust binary
      # (MIPS is backwards compatible; o32 binaries run on 64-bit guests). C
      # tools (console/busybox) still build natively for mips64.
      rustBuildArch = archKey:
        {
          mips64eb = "mipseb";
          mips64el = "mipsel";
        }.${archKey} or archKey;

      mkGuesthopper = archKey:
        import ./src/mk-guest-rust-tool.nix {
          crossPkgs = mkMuslCrossPkgs (rustBuildArch archKey);
          src = guesthopper;
          pname = "guesthopper";
          version = "0.0.1";
        };
      guesthopperBins = lib.mapAttrs (archKey: _: mkGuesthopper archKey) archMatrix;
      guesthopperPackages = builtins.listToAttrs (
        lib.mapAttrsToList
          (archKey: _: {
            name = "guesthopper-${archMatrix.${archKey}.penguinName}";
            value = guesthopperBins.${archKey};
          })
          archMatrix
      );

      # vpnguin: multi-call binary "vsock_vpn" (penguin renames it "vpn"). Guest
      # runs `vpn guest` (all arches); host runs `vpn host` from the x86_64 build
      # (its pcap deps are cfg(x86_64/aarch64)-gated, compiled in automatically).
      mkVpnguin = archKey:
        import ./src/mk-guest-rust-tool.nix {
          crossPkgs = mkMuslCrossPkgs (rustBuildArch archKey);
          src = vpnguin;
          pname = "vsock_vpn";
          version = "0.1.2";
        };
      vpnguinBins = lib.mapAttrs (archKey: _: mkVpnguin archKey) archMatrix;
      vpnguinPackages = builtins.listToAttrs (
        lib.mapAttrsToList
          (archKey: _: {
            name = "vpnguin-${archMatrix.${archKey}.penguinName}";
            value = vpnguinBins.${archKey};
          })
          archMatrix
      );

      # --- busybox (forked, static-musl kconfig + libhc header) -------------
      mkBusybox = archKey:
        import ./src/mk-busybox.nix {
          crossPkgs = mkMuslCrossPkgs archKey;
          src = busybox;
          inherit libhc;
        };
      busyboxBins = lib.mapAttrs (archKey: _: mkBusybox archKey) archMatrix;
      busyboxPackages = builtins.listToAttrs (
        lib.mapAttrsToList
          (archKey: _: {
            name = "busybox-${archMatrix.${archKey}.penguinName}";
            value = busyboxBins.${archKey};
          })
          archMatrix
      );

      mkDropinSysroot = archKey:
        import ./src/mk-dropin-sysroot.nix {
          inherit pkgs;
          archSpec = archMatrix.${archKey};
          muslCrossPkgs = mkMuslCrossPkgs archKey;
        };

      dropinSysroots = lib.mapAttrs (archKey: _: mkDropinSysroot archKey) archMatrix;

      distRoot = import ./src/mk-dist-root.nix {
        inherit pkgs archMatrix archClosures dropinSysroots
          consoleBins guesthopperBins vpnguinBins busyboxBins;
        guesthopperSrc = guesthopper;
        libnvramSrc = libnvram;
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
        // consolePackages
        // guesthopperPackages
        // vpnguinPackages
        // busyboxPackages
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
