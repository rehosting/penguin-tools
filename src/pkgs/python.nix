pkgs:

let
  python = pkgs.python3;
  version = python.pythonVersion;
in
pkgs.runCommand "cpython-runtime-${version}"
  {
    nativeBuildInputs = with pkgs.buildPackages; [
      coreutils
      findutils
      gnugrep
      gnused
    ];
    meta.mainProgram = "python3";
  }
  ''
    set -euo pipefail

    mkdir -p "$out/bin" "$out/lib"

    cp -L ${python}/bin/python3 "$out/bin/python3"
    if [ -e ${python}/bin/python${version} ]; then
      cp -L ${python}/bin/python${version} "$out/bin/"
    fi

    if ls ${python}/lib/libpython${version}*.so* >/dev/null 2>&1; then
      cp -aL ${python}/lib/libpython${version}*.so* "$out/lib/"
    fi

    cp -aL ${python}/lib/python${version} "$out/lib/"

    # Files copied from the read-only /nix/store keep their 0444/0555 modes;
    # make the tree writable so the rm/delete/sed -i fixups below can run.
    chmod -R u+w "$out"

    find "$out" -type d -name __pycache__ -prune -exec rm -rf {} +
    find "$out" -type f \( -name '*.a' -o -name '*.la' -o -name '*-config' \) -delete

    if grep -Irl -- ${python} "$out" >/dev/null 2>&1; then
      grep -IrlZ -- ${python} "$out" | xargs -0r sed -i "s|${python}|$out|g"
    fi

    # subprocess.py and ctypes' fetch_macholib hardcode the build sysroot's
    # shell. On the guest the shell lives at /bin/sh. (Other residual
    # build-time /nix/store references in this tree -- sysconfigdata, the
    # libpython PREFIX baked into rodata, etc. -- are neutralized generically
    # by the bundle's store-path scrub.)
    grep -IrlZ -aP '/nix/store/[a-z0-9]{32}-[^/]*/bin/sh' "$out" | xargs -0r \
      sed -i -E 's,/nix/store/[a-z0-9]{32}-[^/]*/bin/sh,/bin/sh,g'

    # pip's EXTERNALLY-MANAGED marker is meaningless on the guest.
    rm -f "$out/lib/python${version}/EXTERNALLY-MANAGED"
  ''
