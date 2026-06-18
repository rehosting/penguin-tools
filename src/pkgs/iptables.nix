pkgs:

# nixpkgs' iptables is a multi-call binary set: bin/iptables is a symlink to
# xtables-nft-multi, a single executable that dispatches on basename(argv[0]).
# The bundler stages getExe (bin/iptables) with `cp -L`, copying the real multi
# binary under the name "iptables", so argv[0] dispatch still selects the
# nftables backend when it runs as /igloo/utils/iptables on the guest. The
# NEEDED libs (libmnl, libnftnl, libc) are picked up and staged into dylibs by
# normalize_elf. meta.mainProgram is already "iptables".
pkgs.iptables
