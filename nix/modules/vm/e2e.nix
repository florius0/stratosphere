{ ... }:
{
  perSystem =
    { pkgs, vmImages, ... }:
    let
      e2e = import ../../features/vm/e2e/package.nix {
        inherit pkgs;
        vmSpec = vmImages.spec;
      };
    in
    {
      apps.e2e-native = e2e.nativeApp;
      apps.e2e-vm = e2e.vmApp;
      checks.e2e-wrappers = e2e.tests;
      stratosphere.toolingChecks.e2e-wrappers = e2e.tests;
    };
}
