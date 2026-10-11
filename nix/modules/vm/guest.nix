{ ... }:
{
  perSystem =
    { pkgs, vmImages, ... }:
    let
      guest = import ../../features/vm/guest/package.nix {
        inherit pkgs;
        guestUser = vmImages.spec.guestUser;
      };
    in
    {
      _module.args.vmGuest = guest;
      checks.vm-guest = guest.tests;
    };
}
