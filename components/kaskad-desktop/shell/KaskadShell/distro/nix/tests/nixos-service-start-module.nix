{
  self,
  pkgs,
  ...
}:
let
  fakeKaskad = pkgs.writeShellScriptBin "kaskad-shell" ''
    printf '%s\n' "$@" > /tmp/kaskad-shell-service-args
    exec ${pkgs.coreutils}/bin/sleep 300
  '';
in
pkgs.testers.runNixOSTest {
  name = "kaskad-shell-nixos-service-start-module";

  nodes.machine = {
    imports = [
      self.nixosModules.kaskad-shell
    ];

    users.users.kaskad = {
      isNormalUser = true;
      linger = true;
      extraGroups = [ "wheel" ];
    };

    programs.kaskad-shell = {
      enable = true;
      package = fakeKaskad;
      systemd = {
        enable = true;
        target = "default.target";
      };
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")

    machine.succeed("systemctl --machine=kaskad@ --user start kaskad-shell.service")
    machine.wait_until_succeeds("systemctl --machine=kaskad@ --user is-active kaskad-shell.service")
    machine.wait_until_succeeds("test -f /tmp/kaskad-shell-service-args")
    machine.succeed("grep -Fx run /tmp/kaskad-shell-service-args")
    machine.succeed("grep -Fx -- --session /tmp/kaskad-shell-service-args")
  '';
}
