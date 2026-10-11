{ ... }:
{
  perSystem =
    {
      pkgs,
      vmImages,
      vmGuest,
      ...
    }:
    let
      provisioning = import ../../features/vm/provisioning/package.nix {
        inherit pkgs;
        images = vmImages;
        guest = vmGuest;
      };
    in
    {
      apps.vm-provisioning = provisioning.app;
      checks.vm-provisioning = provisioning.tests;
      stratosphere.toolingChecks.vm-provisioning = provisioning.tests;
    };
}
