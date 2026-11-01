{
  description = "Kaskad Shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      goModVersion =
        let
          content = builtins.readFile ./core/go.mod;
          lines = builtins.filter builtins.isString (builtins.split "\n" content);
          goLines = builtins.filter (l: builtins.match "go [0-9]+\\..*" l != null) lines;
          matched =
            if goLines != [ ] then builtins.match "go ([0-9]+)\\.([0-9]+).*" (builtins.head goLines) else null;
        in
        if matched != null then
          {
            major = builtins.elemAt matched 0;
            minor = builtins.elemAt matched 1;
          }
        else
          {
            major = "1";
            minor = "25";
          };
      goForPkgs = pkgs: pkgs.${"go_${goModVersion.major}_${goModVersion.minor}"};
      forEachSystem =
        fn:
        nixpkgs.lib.genAttrs [ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ] (
          system: fn system nixpkgs.legacyPackages.${system}
        );
      forEachLinuxSystem =
        fn:
        nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
          system: fn system nixpkgs.legacyPackages.${system}
        );

      mkModuleWithKaskadPkgs =
        modulePath:
        args@{ pkgs, ... }:
        {
          imports = [
            (import modulePath (args // { kaskadShellPkgs = buildKaskadPkgs pkgs; }))
          ];
        };

      mkQmlImportPath =
        pkgs: qmlPkgs:
        pkgs.lib.concatStringsSep ":" (map (o: "${o}/${pkgs.qt6.qtbase.qtQmlPrefix}") qmlPkgs);

      mkQtPluginPath =
        pkgs: qtPkgs:
        pkgs.lib.concatStringsSep ":" (map (o: "${o}/${pkgs.qt6.qtbase.qtPluginPrefix}") qtPkgs);

      qmlPkgs =
        pkgs: with pkgs.kdePackages; [
          kirigami.unwrapped
          sonnet
          qtmultimedia
          qtimageformats
          kimageformats
        ];

      # Allows downstream modules to provide their own 'pkgs' (with overlays)
      # instead of being forced to use the flake's locked nixpkgs.
      mkKaskadShell =
        pkgs:
        let
          mkDate =
            longDate:
            pkgs.lib.concatStringsSep "-" [
              (builtins.substring 0 4 longDate)
              (builtins.substring 4 2 longDate)
              (builtins.substring 6 2 longDate)
            ];
          version =
            let
              rawVersion = pkgs.lib.removePrefix "v" (pkgs.lib.trim (builtins.readFile ./quickshell/VERSION));
              cleanVersion = builtins.replaceStrings [ " " ] [ "" ] rawVersion;
              dateSuffix = "+date=" + mkDate (self.lastModifiedDate or "19700101");
              revSuffix = "_" + (self.shortRev or "dirty");
            in
            "${cleanVersion}${dateSuffix}${revSuffix}";
        in
        pkgs.lib.makeOverridable (
          {
            extraQtPackages ? [ ],
          }:
          (pkgs.buildGoModule.override { go = goForPkgs pkgs; }) (
            let
              rootSrc = ./.;
              qtPackages = (qmlPkgs pkgs) ++ extraQtPackages;
            in
            {
              inherit version;
              pname = "kaskad-shell";
              src = ./core;
              vendorHash = "sha256-G0KCUaNwjWfLcSnb68TMXjpB2xxwheXgrBkFEzcSZTc=";

              subPackages = [ "cmd/kaskad-shell" ];

              ldflags = [
                "-s"
                "-w"
                "-X 'main.Version=${version}'"
              ];

              nativeBuildInputs = with pkgs; [
                installShellFiles
                makeWrapper
              ];

              postInstall = ''
                mkdir -p $out/share/quickshell/kaskad-shell
                cp -r ${rootSrc}/quickshell/. $out/share/quickshell/kaskad-shell/

                rm -f $out/share/quickshell/kaskad-shell/KaskadCommon
                cp -r ${rootSrc}/kaskad-qml-common/KaskadCommon $out/share/quickshell/kaskad-shell/KaskadCommon
                chmod -R u+w $out/share/quickshell/kaskad-shell/KaskadCommon

                chmod u+w $out/share/quickshell/kaskad-shell/VERSION
                echo "${version}" > $out/share/quickshell/kaskad-shell/VERSION

                # Install desktop file and icon
                install -D ${rootSrc}/assets/kaskad-shell-open.desktop \
                  $out/share/applications/kaskad-shell-open.desktop
                install -D ${rootSrc}/assets/com.kaskadlinux.kaskad-shell.desktop \
                  $out/share/applications/com.kaskadlinux.kaskad-shell.desktop
                install -D ${rootSrc}/assets/com.kaskadlinux.kaskad-shell.notepad.desktop \
                  $out/share/applications/com.kaskadlinux.kaskad-shell.notepad.desktop
                install -D ${rootSrc}/core/assets/kaskadlogo.svg \
                  $out/share/hicolor/scalable/apps/kaskadlogo.svg

                wrapProgram $out/bin/kaskad-shell \
                  --add-flags "-c $out/share/quickshell/kaskad-shell" \
                  --prefix "NIXPKGS_QT6_QML_IMPORT_PATH" ":" "${mkQmlImportPath pkgs qtPackages}" \
                  --prefix "QT_PLUGIN_PATH" ":" "${mkQtPluginPath pkgs qtPackages}"

                install -Dm644 ${rootSrc}/assets/systemd/kaskad-shell.service \
                  $out/lib/systemd/user/kaskad-shell.service

                substituteInPlace $out/lib/systemd/user/kaskad-shell.service \
                  --replace-fail /usr/bin/kaskad-shell $out/bin/kaskad-shell \
                  --replace-fail /usr/bin/pkill ${pkgs.procps}/bin/pkill

                substituteInPlace $out/share/quickshell/kaskad-shell/assets/pam/fprint \
                  --replace-fail pam_fprintd.so ${pkgs.fprintd}/lib/security/pam_fprintd.so \
                  --replace-fail pam_deny.so ${pkgs.pam}/lib/security/pam_deny.so \
                  --replace-fail pam_permit.so ${pkgs.pam}/lib/security/pam_permit.so

                substituteInPlace $out/share/quickshell/kaskad-shell/assets/pam/u2f \
                  --replace-fail pam_u2f.so ${pkgs.pam_u2f}/lib/security/pam_u2f.so \
                  --replace-fail pam_deny.so ${pkgs.pam}/lib/security/pam_deny.so \
                  --replace-fail pam_permit.so ${pkgs.pam}/lib/security/pam_permit.so

                substituteInPlace $out/share/quickshell/kaskad-shell/assets/pam/other \
                  --replace-fail pam_deny.so ${pkgs.pam}/lib/security/pam_deny.so

                installShellCompletion --cmd kaskad-shell \
                  --bash <($out/bin/kaskad-shell completion bash) \
                  --fish <($out/bin/kaskad-shell completion fish) \
                  --zsh <($out/bin/kaskad-shell completion zsh)
              '';

              meta = {
                description = "Desktop shell for wayland compositors built with Quickshell & GO";
                homepage = "https://kaskadlinux.com";
                changelog = "https://github.com/lyrka-meow/KaskadOS/releases/tag/v${version}";
                license = pkgs.lib.licenses.mit;
                mainProgram = "kaskad-shell";
                platforms = pkgs.lib.platforms.linux;
              };
            }
          )
        ) { };

      buildKaskadPkgs = pkgs: {
        kaskad-shell = mkKaskadShell pkgs;
      };
    in
    {
      packages = forEachSystem (
        system: pkgs: {
          kaskad-shell = mkKaskadShell pkgs;
          default = self.packages.${system}.kaskad-shell;
          quickshell = builtins.warn "kaskad-shell: the package Quickshell is not included in the Kaskad flake anymore. We recommend you to use the one from nixos-unstable branch of Nixpkgs or the upstream flake." pkgs.quickshell;
        }
      );

      lib = { inherit mkKaskadShell buildKaskadPkgs; };

      homeModules.kaskad-shell = mkModuleWithKaskadPkgs ./distro/nix/home.nix;

      homeModules.default = self.homeModules.kaskad-shell;

      homeModules.niri = import ./distro/nix/niri.nix;

      nixosModules.kaskad-shell = mkModuleWithKaskadPkgs ./distro/nix/nixos.nix;

      nixosModules.default = self.nixosModules.kaskad-shell;

      devShells = forEachSystem (
        system: pkgs:
        let
          devQmlPkgs = with pkgs;
          [
            quickshell
            kdePackages.qtdeclarative
          ]
          ++ (qmlPkgs pkgs);
        in
        {
          default = pkgs.mkShell {
            buildInputs =
              with pkgs;
              [
                (goForPkgs pkgs)
                go-mockery
                gopls
                delve
                go-tools
                gnumake

                prek
                uv # for prek
                shellcheck

                # Nix development tools
                nixd
                nil
              ]
              ++ devQmlPkgs;

            shellHook = ''
              touch quickshell/.qmlls.ini 2>/dev/null
              if [ ! -f .git/hooks/pre-commit ]; then prek install; fi
            '';

            QML2_IMPORT_PATH = mkQmlImportPath pkgs devQmlPkgs;
            QT_PLUGIN_PATH = mkQtPluginPath pkgs devQmlPkgs;
          };
        }
      );

      nixosTests = forEachLinuxSystem (
        system: pkgs:
        import ./distro/nix/tests {
          inherit
            self
            pkgs
            ;
          lib = pkgs.lib;
        }
      );
    };
}
