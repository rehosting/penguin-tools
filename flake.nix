{
  description = "Penguin guest tools builder";

  nixConfig = {
    extra-substituters = [ "https://rehosting-tools.cachix.org" ];
    extra-trusted-public-keys = [
      "rehosting-tools.cachix.org-1:iNKSaFwG7MfGn6Fk7oTmIcLHqfffQ+cQIE5gWc6MlY0="
    ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/b6067cc0127d4db9c26c79e4de0513e58d0c40c9";

  # The forked guest utilities (console, busybox, guesthopper, vpnguin) and the
  # libnvram source used to be vendored + cross-built here. They now each build
  # themselves via their own flake and penguin consumes them directly, so
  # penguin-tools is back to what it genuinely builds: the debugging-tool
  # closures (python3/strace/gdb/ltrace/iptables) + drop-in musl sysroots.

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

      # Generic cross-compilation fixes (gnutls' target-binary doc build, the
      # gobject-introspection checkPhase). These also have to reach buildPackages
      # (g-i is a native build tool), so they go in `overlays`.
      hostOverlays = import ./src/cross-overlays.nix;

      # Runtime-gate the time vDSO in glibc for 32-bit mips/arm guests: on a
      # pre-5.1 guest kernel PANDA emulates the clocksource unreliably, so
      # glibc's clock_gettime spins or ENOSYSes (penguin#876). The patch leaves
      # the dl_vdso_* clock pointers NULL below kernel 5.1.0 (falling back to the
      # syscall) and keeps the vDSO fast path at/above it.
      glibcVdsoGateOverlay = final: prev: {
        glibc = prev.glibc.overrideAttrs (o: {
          patches = (o.patches or [ ]) ++ [ ./src/patches/force-syscall-clock.patch ];
        });
      };

      # The 32-bit arches that present the issue. 64-bit arches use the native
      # 64-bit clock_gettime and keep the pinned glibc (byte-identical closures).
      #
      # The overlay is selected per-arch HERE (not inside the overlay via a
      # platform predicate), so x86_64 receives an EMPTY crossOverlays list.
      # That is mandatory, not stylistic: x86_64's crossSystem config equals the
      # x86_64-linux build host's -- a degenerate same-system cross that nixpkgs
      # mishandles (NixOS/nixpkgs#265121). A non-empty crossOverlays on x86_64
      # first makes the glibc fixpoint infinitely recurse at eval; and even if
      # forced past that (dummyValueToForceCrossCompiling, turning x86_64 into a
      # genuine self-cross), the *build* then fails -- the same-system cross gcc
      # wrapper picks the unwrapped build compiler's target-prefixed gcc and
      # "cannot create executables" (attr/coreutils/... all fail). Unlike our
      # real crosses (different CPU, wrapper fine), x86_64 must stay a native
      # build -> empty crossOverlays -> the list is gated from outside.
      glibcPatchArches = [ "mipsel" "mipseb" "armel" ];

      mkCrossPkgs = archKey:
        import nixpkgs {
          inherit system;
          config.allowUnsupportedSystem = true;
          overlays = hostOverlays;
          crossOverlays =
            lib.optional (builtins.elem archKey glibcPatchArches) glibcVdsoGateOverlay;
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
          # The guest interpreter ships a curated debugging / system / networking
          # toolkit on top of the slim stdlib. All verified to cross-build across
          # the full arch set (incl. the C-extension ones cffi/psutil/netifaces).
          # gdb below keeps the bare slimPython for its pretty-printers (a
          # withPackages env would drag these into gdb's closure for nothing).
          #
          # NB scapy is intentionally NOT here: its nixpkgs cross-closure pulls a
          # native audio chain (sox -> libao -> libcap -> go) and `go` does not
          # cross-compile for mipsel ("cannot find runtime/cgo", -mips32r2
          # conflict), breaking the 32-bit-MIPS closure. pyroute2 (netlink) + dpkt
          # (packet parsing) cover the networking need without that closure.
          guestPython = slimPython.withPackages (ps: with ps; [
            requests    # HTTP client
            cffi        # C interop / poke libc & structs from Python
            psutil      # processes, memory, network connections, system stats
            netifaces   # interface / address enumeration
            pyroute2    # netlink: links, routes, netns, tc
            dpkt        # fast packet parsing
          ]);
          # gdb pinned to 16.3 rather than nixpkgs' 17.1: 17.1 does not
          # cross-build across our arch set (aarch64 struct user_gcs
          # redefinition vs modern kernel headers, ser-unix.c custom-baudrate
          # termios fields, and gdbserver's in-process agent erroring out on
          # armv7l). 16.3 is what Alpine/Buildroot ship and predates all of
          # that. Plus: disable the (unused, not-everywhere-supported)
          # in-process agent, fix the mips sgidefs include, and disable
          # debuginfod -- a client feature that fetches symbols from a remote
          # server, which also drops the heavy elfutils -> libmicrohttpd ->
          # gnutls chain and shrinks the closure.
          #
          # pythonSupport is left ON -- it powers gdb's pretty-printers, the
          # genuinely useful client feature. Its python is pointed at slimPython
          # (rather than the default full python3) so the closure carries a
          # single python: pretty-printers only need the stdlib, which slimPython
          # keeps, avoiding a second ~114M unstripped python.
          #
          # source-highlight is dropped, though: gdb's nixpkgs expr links it
          # unconditionally (no flag), but all it does is syntax-color source
          # listings -- and it is the *sole* path by which boost (~15M) and
          # icu4c (~39M) enter the closure. Filtering it out of buildInputs makes
          # gdb's configure auto-disable it, removing ~57M/arch while leaving
          # pretty-printers untouched.
          gdbDrv = (crossPkgs.gdbHostCpuOnly.override { enableDebuginfod = false; python3 = slimPython; }).overrideAttrs (prev: {
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
          });
          base = {
            python3 = {
              drv = guestPython;
              exe = "${guestPython}/bin/python3";
            };
            strace = {
              drv = crossPkgs.strace;
              exe = "${crossPkgs.strace}/bin/strace";
            };
            # Ship both the full gdb client (for on-guest interactive debugging)
            # and gdbserver (for remote debugging from the host), from the one
            # gdbDrv built above.
            gdb = {
              drv = gdbDrv;
              exe = "${gdbDrv}/bin/gdb";
            };
            gdbserver = {
              drv = gdbDrv;
              exe = "${gdbDrv}/bin/gdbserver";
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
        let crossPkgs = mkCrossPkgs archKey;
        in import ./src/mk-arch-closure.nix {
          inherit pkgs crossPkgs;
          archSpec = archMatrix.${archKey};
          tools = mkTools archKey crossPkgs;
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
