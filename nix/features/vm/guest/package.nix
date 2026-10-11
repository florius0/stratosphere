{
  pkgs,
  guestUser ? "admin",
}:
assert builtins.match "[a-z_][a-z0-9_-]*" guestUser != null;
let
  settings = {
    user = guestUser;
    autoLoginUser = guestUser;
    home = "/Users/${guestUser}";
    shell = "/bin/zsh";
    screensaverIdleTime = 0;
    sleep = 0;
    displaySleep = 0;
  };
  native = {
    sysctl = "/usr/sbin/sysctl";
    id = "/usr/bin/id";
    base64 = "/usr/bin/base64";
    dscl = "/usr/bin/dscl";
    sysadminctl = "/usr/sbin/sysadminctl";
    defaults = "/usr/bin/defaults";
    sudo = "/usr/bin/sudo";
    launchctl = "/bin/launchctl";
    pmset = "/usr/bin/pmset";
    mkdir = "/bin/mkdir";
    chmod = "/bin/chmod";
    chown = "/usr/sbin/chown";
    stat = "/usr/bin/stat";
    awk = "/usr/bin/awk";
    mktemp = "/usr/bin/mktemp";
    cmp = "/usr/bin/cmp";
    mv = "/bin/mv";
    rm = "/bin/rm";
  };
  makeScript =
    {
      commands ? native,
      home ? settings.home,
    }:
    pkgs.replaceVars ./scripts/provision.sh (
      commands
      // {
        inherit home;
        inherit (settings) user autoLoginUser;
        shell = pkgs.lib.escapeShellArg settings.shell;
        screensaverIdleTime = toString settings.screensaverIdleTime;
        sleep = toString settings.sleep;
        displaySleep = toString settings.displaySleep;
      }
    );
in
{
  configuration = settings;
  script = makeScript { };
  tests = import ./tests.nix { inherit pkgs makeScript; };
}
