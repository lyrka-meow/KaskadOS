{
  self,
  pkgs,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "kaskad-shell-nixos-module";

  nodes.machine = {
    imports = [
      self.nixosModules.kaskad-shell
    ];

    users.users.kaskad = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };

    programs.kaskad-shell = {
      enable = true;
      systemd.enable = true;
      lockscreen.securityKey.enable = true;
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target")

    machine.succeed("command -v kaskad-shell")
    machine.succeed("command -v quickshell")
    machine.succeed("su -- kaskad -c 'kaskad-shell --help >/dev/null'")
    machine.succeed("test -f /run/current-system/sw/lib/systemd/user/kaskad-shell.service")
    machine.succeed("grep -q 'lib/security/pam_u2f.so cue' /etc/pam.d/kaskad-shell-u2f")

    payload = json.loads(machine.succeed("su -- kaskad -c 'kaskad-shell doctor --json'"))
    t.assertIn("summary", payload)
    t.assertIsInstance(payload.get("results"), list)
  '';
}
