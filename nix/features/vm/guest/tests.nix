{ pkgs, makeScript }:
let
  native = pkgs.writeShellApplication {
    name = "guest-native";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    runtimeEnv = {
      COREUTILS_BASE64 = "${pkgs.coreutils}/bin/base64";
      COREUTILS_STAT = "${pkgs.coreutils}/bin/stat";
    };
    text = builtins.readFile ./tests/native.sh;
  };
  commands =
    builtins.listToAttrs (
      map
        (name: {
          inherit name;
          value = "${native}/bin/guest-native ${name}";
        })
        [
          "sysctl"
          "id"
          "base64"
          "dscl"
          "sysadminctl"
          "defaults"
          "sudo"
          "launchctl"
          "pmset"
          "chown"
          "stat"
        ]
    )
    // {
      mkdir = "${pkgs.coreutils}/bin/mkdir";
      chmod = "${pkgs.coreutils}/bin/chmod";
      awk = "${pkgs.gawk}/bin/awk";
      mktemp = "${pkgs.coreutils}/bin/mktemp";
      cmp = "${pkgs.diffutils}/bin/cmp";
      mv = "${pkgs.coreutils}/bin/mv";
      rm = "${pkgs.coreutils}/bin/rm";
    };
  script = makeScript {
    inherit commands;
    home = "$TEST_HOME";
  };
  productionScript = makeScript { };
in
pkgs.runCommand "vm-guest-provisioning-behavior" {
  PRODUCTION_SCRIPT = productionScript;
  GUEST_SCRIPT = script;
  nativeBuildInputs = [
    pkgs.bash
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.shellcheck
  ];
} (builtins.readFile ./tests/run.sh)
