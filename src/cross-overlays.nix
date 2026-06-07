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
  # --disable-doc skips the doc build, so neither the "man" nor "devdoc"
  # outputs get populated. Upstream couples these: it only passes
  # --disable-doc for MinGW and drops both outputs in the same case. Mirror
  # that here, or Nix fails with "failed to produce output path for output
  # 'devdoc'" (then 'man').
  (self: super: {
    gnutls = super.gnutls.overrideAttrs (o: {
      configureFlags = (o.configureFlags or [ ]) ++ [ "--disable-doc" ];
      outputs = builtins.filter (x: x != "man" && x != "devdoc") (o.outputs or [ "out" ]);
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

  # argp-standalone (pulled in by elfutils on musl) builds testsuite example
  # binaries with stack-protector on. On some 32-bit musl targets (e.g.
  # powerpc) the toolchain doesn't provide __stack_chk_fail_local, so linking
  # the examples fails with "undefined reference to __stack_chk_fail_local".
  # Only the static lib is consumed downstream, so just drop the hardening.
  (self: super: {
    argp-standalone = super.argp-standalone.overrideAttrs (o: {
      hardeningDisable = (o.hardeningDisable or [ ]) ++ [ "stackprotector" ];
    });
  })
]
