{ pkgs, distRoot }:

pkgs.runCommand "penguin-tools.tar.gz"
  {
    nativeBuildInputs = with pkgs.buildPackages; [ gnutar gzip ];
  }
  ''
    set -euo pipefail
    tar \
      --sort=name \
      --owner=0 \
      --group=0 \
      --numeric-owner \
      --mtime='@1' \
      -czf "$out" \
      -C ${distRoot} \
      igloo_static
  ''
