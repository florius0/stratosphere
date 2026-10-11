{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      images = import ../../features/vm/images/package.nix { inherit pkgs; };
    in
    {
      _module.args.vmImages = images;
      checks.vm-images = images.tests;
      stratosphere.toolingChecks.vm-images = images.tests;
    };
}
