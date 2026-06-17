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

      mkCrossPkgs = archKey:
        import nixpkgs {
          inherit system;
          config.allowUnsupportedSystem = true;
          crossSystem = archMatrix.${archKey}.crossSystem;
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
            gdbserver = {
              drv = crossPkgs.gdbHostCpuOnly;
              exe = "${crossPkgs.gdbHostCpuOnly}/bin/gdbserver";
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

      distRoot = import ./src/mk-dist-root.nix {
        inherit pkgs archMatrix archClosures;
      };

      dist = import ./src/mk-dist-tarball.nix {
        inherit pkgs distRoot;
      };

      # Per-arch closures exposed individually for inspection / partial builds.
      closurePackages = builtins.listToAttrs (
        lib.mapAttrsToList
          (archKey: closure: {
            name = "closure-${archMatrix.${archKey}.penguinName}";
            value = closure;
          })
          archClosures
      );
    in
    {
      packages.${system} =
        closurePackages
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
