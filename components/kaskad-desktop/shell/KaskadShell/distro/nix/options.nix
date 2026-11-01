{
  lib,
  kaskadShellPkgs,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  path = [
    "programs"
    "kaskad-shell"
  ];
  builtInRemovalMessage = "This is built into Kaskad Shell and doesn't need additional dependencies.";
in
{
  imports = [
    (lib.mkRemovedOptionModule (path ++ [ "enableBrightnessControl" ]) builtInRemovalMessage)
    (lib.mkRemovedOptionModule (path ++ [ "enableColorPicker" ]) builtInRemovalMessage)
    (lib.mkRemovedOptionModule (path ++ [ "enableClipboard" ]) builtInRemovalMessage)
    (lib.mkRemovedOptionModule (
      path ++ [ "enableSystemSound" ]
    ) "qtmultimedia is now included on kaskad-shell package.")
  ];

  options.programs.kaskad-shell = {
    enable = lib.mkEnableOption "KaskadShell";
    package = lib.mkPackageOption kaskadShellPkgs "kaskad-shell" {
      extraDescription = "The KaskadShell package to use (defaults to be built from source)";
    };

    systemd = {
      enable = lib.mkEnableOption "KaskadShell systemd startup";
      restartIfChanged = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Auto-restart kaskad-shell.service when kaskad-shell changes";
      };
    };

    dgop = {
      package = lib.mkPackageOption pkgs "dgop" { };
    };

    enableSystemMonitoring = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Add needed dependencies to use system monitoring widgets";
    };

    enableVPN = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Add needed dependencies to use the VPN widget";
    };

    enableDynamicTheming = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Add needed dependencies to have dynamic theming support";
    };

    enableAudioWavelength = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Add needed dependencies to have audio wavelength support";
    };

    enableCalendarEvents = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Add calendar events support via khal";
    };

    enableClipboardPaste = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Deprecated: paste is built into kaskad-shell; no extra dependencies needed. Kept as a no-op for compatibility.";
    };

    quickshell = {
      package = lib.mkPackageOption pkgs "quickshell" {
        extraDescription = "(we recommend at least 0.3.0, currently available in nixos-unstable)";
      };
    };

  };
}
