{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      docs = import ../features/documentation/package.nix { inherit pkgs; };
    in
    {
      _module.args.docs = docs;
      apps.docs = docs.app;
      checks.documentation = docs.tests;
      stratosphere.toolingChecks.documentation = docs.tests;
      checks.documentation-source =
        pkgs.runCommand "stratosphere-documentation-source"
          {
            nativeBuildInputs = [ docs.package ];
          }
          ''
            cp -R ${self}/. source
            cd source
            stratosphere-docs
            touch "$out"
          '';
    };
}
