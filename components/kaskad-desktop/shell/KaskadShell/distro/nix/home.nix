{
  config,
  pkgs,
  lib,
  ...
}@args:
let
  cfg = config.programs.kaskad-shell;
  jsonFormat = pkgs.formats.json { };
  common = import ./common.nix {
    inherit
      config
      pkgs
      lib
      ;
  };
in
{
  imports = [
    (import ./options.nix args)
    (lib.mkRemovedOptionModule [
      "programs"
      "kaskad-shell"
      "enableNightMode"
    ] "Night mode is now always available")
    (lib.mkRemovedOptionModule [
      "programs"
      "kaskad-shell"
      "default"
      "settings"
    ] "Default settings have been removed and been replaced with programs.kaskad-shell.settings")
    (lib.mkRemovedOptionModule [
      "programs"
      "kaskad-shell"
      "default"
      "session"
    ] "Default session has been removed and been replaced with programs.kaskad-shell.session")
    (lib.mkRenamedOptionModule
      [ "programs" "kaskad-shell" "enableSystemd" ]
      [ "programs" "kaskad-shell" "systemd" "enable" ]
    )
  ];

  options.programs.kaskad-shell = {
    settings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = "KaskadShell configuration settings as an attribute set, to be written to ~/.config/KaskadShell/settings.json.";
    };

    clipboardSettings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = "KaskadShell clipboard settings as an attribute set, to be written to ~/.config/KaskadShell/clsettings.json.";
    };

    session = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = "KaskadShell session settings as an attribute set, to be written to ~/.local/state/KaskadShell/session.json.";
    };

    systemd.target = lib.mkOption {
      type = lib.types.str;
      default = config.wayland.systemd.target;
      defaultText = lib.literalExpression "config.wayland.systemd.target";
      description = "Systemd target to bind to.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.quickshell = {
      enable = true;
      inherit (cfg.quickshell) package;
    };

    systemd.user.services.kaskad-shell = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "KaskadShell";
        PartOf = [ cfg.systemd.target ];
        After = [ cfg.systemd.target ];
      };

      Service = {
        ExecStart = lib.getExe cfg.package + " run --session";
        Restart = "on-failure";
      };

      Install.WantedBy = [ cfg.systemd.target ];
    };

    xdg.stateFile."KaskadShell/session.json" = lib.mkIf (cfg.session != { }) {
      source = jsonFormat.generate "session.json" cfg.session;
    };

    xdg.configFile = {
      "KaskadShell/settings.json" = lib.mkIf (cfg.settings != { }) {
        source = jsonFormat.generate "settings.json" cfg.settings;
      };
      "KaskadShell/clsettings.json" = lib.mkIf (cfg.clipboardSettings != { }) {
        source = jsonFormat.generate "clsettings.json" cfg.clipboardSettings;
      };
    };
    home.packages = common.packages;
  };
}
