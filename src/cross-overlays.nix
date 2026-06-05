[
  # Disable libfuse's /etc/mtab handling with util-linux's mount command.
  (self: super: {
    fuse3 = super.fuse3.overrideAttrs (o: {
      # The disable-mtab option is ignored upstream, so disable mtab manually.
      mesonFlags = (o.mesonFlags or [ ]) ++ [ "-Ddisable-mtab=true" ];
      CFLAGS = "-DIGNORE_MTAB=1";
    });
  })

  # Remove the unneeded util-linux dependency to speed up builds.
  (self: super: {
    fuse3 = super.fuse3.override { util-linux = super.emptyDirectory; };
  })

  # The p11-kit tests fail in our single-user Nix setup.
  (self: super: {
    p11-kit = super.p11-kit.overrideAttrs (_: {
      doCheck = false;
    });
  })

  # GnuTLS docs builds run generated target binaries such as lt-errcodes.
  (self: super: {
    gnutls = super.gnutls.overrideAttrs (o: {
      configureFlags = (o.configureFlags or [ ]) ++ [ "--disable-doc" ];
    });
  })

  # Fix musl+loongarch+gdb builds.
  (self: super: {
    musl = super.musl.overrideAttrs (o: {
      patches = (o.patches or [ ]) ++ [ ./patches/musl-loongarch-regset.patch ];
    });
  })

  # Disable unused and broken-on-some-platforms elfutils features.
  (self: super: {
    elfutils = (super.elfutils.override {
      enableDebuginfod = false;
    }).overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ super.buildPackages.pkg-config ];
    });
  })
]
