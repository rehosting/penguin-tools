pkgs:

let
  python = pkgs.python3Minimal;
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

    find "$out" -type d -name __pycache__ -prune -exec rm -rf {} +
    find "$out" -type f \( -name '*.a' -o -name '*.la' -o -name '*-config' \) -delete

    if grep -Irl -- ${python} "$out" >/dev/null 2>&1; then
      grep -IrlZ -- ${python} "$out" | xargs -0r sed -i "s|${python}|$out|g"
    fi
  ''
