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

  niriFlake = builtins.getFlake "github:sodiboo/niri-flake/2bb22af2985e5f3cfd051b3d977ebfbf81126280?narHash=sha256-ooPmu%2B8tqOGh4kozPW4rJC7Y7WM/FHtEY3OK1PoNW7g%3D";

  fakeNiri = (pkgs.writeScriptBin "niri" "") // {
    cargoBuildNoDefaultFeatures = false;
  };
in
pkgs.testers.runNixOSTest {
  name = "kaskad-shell-niri-home-module";

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

    environment.pathsToLink = [
      "/share/applications"
      "/share/xdg-desktop-portal"
    ];

    home-manager.users.kaskad = {
      ...
    }: {
      imports = [
        self.homeModules.kaskad-shell
        niriFlake.homeModules.niri
        self.homeModules.niri
      ];

      home.username = "kaskad";
      home.homeDirectory = "/home/kaskad";
      home.stateVersion = "25.11";

      programs.niri = {
        enable = true;
        package = fakeNiri; # avoids niri from being compiled in the CI
      };

      programs.kaskad-shell = {
        enable = true;
        niri = {
          enableKeybinds = false;
          enableSpawn = true;
        };
      };
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    machine.succeed("su -- kaskad -c 'test -f ~/.config/niri/config.kdl'")
    machine.succeed("su -- kaskad -c 'grep -F \"include optional=true \\\"kaskad-shell/binds.kdl\\\"\" ~/.config/niri/config.kdl'")
    machine.succeed("su -- kaskad -c 'grep -F \"include optional=true \\\"hm.kdl\\\"\" ~/.config/niri/config.kdl'")
    machine.succeed("su -- kaskad -c 'grep -F \"spawn-at-startup\" ~/.config/niri/hm.kdl'")
    machine.succeed("su -- kaskad -c 'grep -F \"\\\"kaskad-shell\\\" \\\"run\\\"\" ~/.config/niri/hm.kdl'")
  '';
}
