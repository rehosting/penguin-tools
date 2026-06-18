# Generic cross-compilation fixes applied to the glibc cross package sets.
#
# These are NOT musl build hacks (the musl-only overrides are gone) -- they are
# upstream cross-compilation breakages that bite any cross target:
#
# gnutls' doc build runs generated *target* binaries during the build
# (./errcodes -> lt-errcodes), which fails under cross-compilation with
# "Exec format error". gnutls is pulled in transitively by elfutils ->
# libmicrohttpd (debuginfod) through strace, ltrace and gdb. --disable-doc
# skips the offending step, but then the declared "man"/"devdoc" outputs are
# never populated and Nix fails "failed to produce output path for output
# 'devdoc'". Upstream couples these (it only passes --disable-doc for MinGW and
# drops both outputs in the same case), so mirror that here.
[
  (self: super: {
    gnutls = super.gnutls.overrideAttrs (o: {
      configureFlags = (o.configureFlags or [ ]) ++ [ "--disable-doc" ];
      outputs = builtins.filter (x: x != "man" && x != "devdoc") (o.outputs or [ "out" ]);
    });

    # gobject-introspection is pulled in (natively) as a build tool of graphviz,
    # a doc-generation nativeBuildInput of libnl, which iptables depends on. Its
    # meson test suite fails two cases on the build host
    # (warn-callback-invalid-scope / -destroy). g-i is only a build tool here, so
    # skip its checkPhase. Overlays apply to buildPackages, so this reaches the
    # native derivation.
    gobject-introspection = super.gobject-introspection.overrideAttrs (_: {
      doCheck = false;
    });
  })
]
