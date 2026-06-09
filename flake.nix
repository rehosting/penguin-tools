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
      overlays = import ./src/cross-overlays.nix;

      mkPkgs = args:
        import nixpkgs ({
          inherit system;
          config.allowUnsupportedSystem = true;
          inherit overlays;
        } // args);

      pkgs = mkPkgs { };
      lib = pkgs.lib;

      toolSpecs = {
        strace = {
          kind = "binary";
          build = crossPkgs: import ./src/pkgs/strace.nix crossPkgs;
        };
        gdbserver = {
          kind = "binary";
          build = crossPkgs: import ./src/pkgs/gdbserver.nix crossPkgs;
        };
        ltrace = {
          kind = "binary";
          build = crossPkgs: import ./src/pkgs/ltrace.nix crossPkgs;
        };
        python = {
          kind = "tree";
          build = crossPkgs: import ./src/pkgs/python.nix crossPkgs;
        };
      };

      mkCrossPkgs = archKey:
        mkPkgs {
          crossSystem = archMatrix.${archKey}.crossSystem;
        };

      rawToolPackages =
        lib.mapAttrs
          (archKey: _: lib.mapAttrs (_: spec: spec.build (mkCrossPkgs archKey)) toolSpecs)
          archMatrix;

      isSupported = archKey: drv:
        !(builtins.elem archKey (drv.passthru.iglooExcludedArchs or [ ]));

      resolveTool = archKey: toolName:
        let
          toolSpec = toolSpecs.${toolName};
          drv = rawToolPackages.${archKey}.${toolName};
          fallbackArchs = drv.passthru.iglooFallbackArchs or { };
          fallbackArch = fallbackArchs.${archKey} or null;
          mkPath = resolvedDrv:
            if toolSpec.kind == "binary" then
              lib.getExe resolvedDrv
            else
              resolvedDrv;
        in
        if isSupported archKey drv then
          {
            inherit (toolSpec) kind;
            inherit drv;
            mode = "copy";
            path = mkPath drv;
          }
        else if fallbackArch != null then
          let
            fallbackDrv = rawToolPackages.${fallbackArch}.${toolName};
          in
          assert isSupported fallbackArch fallbackDrv;
          {
            inherit (toolSpec) kind;
            drv = fallbackDrv;
            mode = "symlink";
            path = mkPath fallbackDrv;
            linkTarget = "../${archMatrix.${fallbackArch}.penguinName}/${toolName}";
          }
        else
          null;

      selectedToolPackages =
        lib.mapAttrs
          (archKey: _:
            lib.filterAttrs (_: tool: tool != null) (
              lib.mapAttrs (toolName: _: resolveTool archKey toolName) toolSpecs
            ))
          archMatrix;

      mkArchBundle = archKey:
        import ./src/mk-arch-bundle.nix {
          inherit pkgs;
          crossPkgs = mkCrossPkgs archKey;
          archSpec = archMatrix.${archKey};
          tools = selectedToolPackages.${archKey};
        };

      archBundles = lib.mapAttrs (archKey: _: mkArchBundle archKey) archMatrix;

      distRoot = import ./src/mk-dist-root.nix {
        inherit pkgs archBundles;
      };

      dist = import ./src/mk-dist-tarball.nix {
        inherit pkgs distRoot;
      };

      individualPackages = builtins.listToAttrs (
        lib.concatMap
          (archKey:
            lib.mapAttrsToList
              (toolName: tool: {
                name = "${toolName}-${archKey}";
                value = tool.drv;
              })
              selectedToolPackages.${archKey})
          (builtins.attrNames archMatrix)
      );
    in
    {
      packages.${system} =
        individualPackages
        // archBundles
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
