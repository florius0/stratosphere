{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      check = import ../features/artifacts/tests.nix { inherit pkgs; };
    in
    {
      _module.args.artifacts = import ../features/artifacts/package.nix { inherit pkgs; };
      checks.artifacts = check;
      stratosphere.toolingChecks.artifacts = check;
    };
}
