pkgs:

# Same multi-call iptables package, but expose the legacy (get/setsockopt)
# entry point instead of the nftables one. getExe resolves
# "${getBin drv}/bin/${drv.meta.mainProgram}", so we only need to override
# meta.mainProgram. Overlay it onto the existing derivation with `//` rather
# than overrideAttrs: `//` leaves drvPath/outPath untouched, so this shares
# iptables' compiled output (no second build) and just stages bin/iptables-legacy
# (-> xtables-legacy-multi) instead of bin/iptables.
let
  iptables = import ./iptables.nix pkgs;
in
iptables // {
  meta = iptables.meta // { mainProgram = "iptables-legacy"; };
}
