{
  self,
  pkgs,
  ...
}:
let
  homeManagerNixosModule =
    (fetchTarball {
      url = "https://github.com/nix-community/home-manager/archive/53ebbdc405acc04acd9bb73ccca462b51ddb8c6d.tar.gz";
      sha256 = "1cqmfgwb3jac2zzv82bwvgypxff1z30xkz9j6qcinkmqf58j3k3b";
    })
    + "/nixos";
in
pkgs.testers.runNixOSTest {
  name = "kaskad-shell-home-manager-module";

  nodes.machine = {
    ...
  }: {
    imports = [
      homeManagerNixosModule
    ];

    users.users.kaskad = {
      isNormalUser = true;
      createHome = true;
      home = "/home/kaskad";
      extraGroups = [ "wheel" ];
    };

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;

    home-manager.users.kaskad = {
      pkgs,
      ...
    }: {
      imports = [
        self.homeModules.kaskad-shell
      ];

      home.username = "kaskad";
      home.homeDirectory = "/home/kaskad";
      home.stateVersion = "25.11";

      programs.kaskad-shell = {
        enable = true;
        systemd = {
          enable = true;
          target = "default.target";
        };

        settings = {
          theme = "integration-test";
        };

        clipboardSettings = {
          maxItems = 10;
        };

        session = {
          startedFrom = "nixos-test";
        };
      };
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target")

    machine.succeed("su -- kaskad -c 'command -v kaskad-shell'")
    machine.succeed("su -- kaskad -c 'test -f ~/.config/KaskadShell/settings.json'")
    machine.succeed("su -- kaskad -c 'test -f ~/.config/KaskadShell/clsettings.json'")
    machine.succeed("su -- kaskad -c 'test -f ~/.local/state/KaskadShell/session.json'")

    settings = json.loads(machine.succeed("su -- kaskad -c 'cat ~/.config/KaskadShell/settings.json'"))
    clipboard = json.loads(machine.succeed("su -- kaskad -c 'cat ~/.config/KaskadShell/clsettings.json'"))
    session = json.loads(machine.succeed("su -- kaskad -c 'cat ~/.local/state/KaskadShell/session.json'"))
    doctor = json.loads(machine.succeed("su -- kaskad -c 'kaskad-shell doctor --json'"))

    t.assertEqual(settings["theme"], "integration-test")
    t.assertEqual(clipboard["maxItems"], 10)
    t.assertEqual(session["startedFrom"], "nixos-test")
    t.assertIsInstance(doctor.get("results"), list)
  '';
}
