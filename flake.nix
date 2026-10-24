{
  description = "Legacy CUDA runtime for voice-changer on x86_64 Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      application = pkgs.runCommand "voice-changer-application" { } ''
        mkdir -p "$out/client/demo"
        cp -R ${./server} "$out/server"
        cp -R ${./client/demo/dist} "$out/client/demo/dist"
        cp -R ${./nix} "$out/nix"
      '';
      runtime = pkgs.buildFHSEnv {
        name = "voice-changer-env";
        unsharePid = true;
        dieWithParent = true;
        targetPkgs =
          p: with p; [
            bashInteractive
            coreutils
            findutils
            git
            cacert
            curl
            python310
            uv
            gcc
            gnumake
            pkg-config
            stdenv.cc.cc.lib
            zlib
            openssl
            libsndfile
            portaudio
            alsa-lib
            libpulseaudio
            pulseaudio
            ffmpeg
            espeak-ng
          ];
        profile = ''
          export PYTHONNOUSERSITE=1
          export UV_PYTHON_DOWNLOADS=never
          export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
          export LD_LIBRARY_PATH="/run/opengl-driver/lib:/usr/lib:/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          export VOICE_CHANGER_ENV_SCRIPT=${./nix/environment.sh}
          source "$VOICE_CHANGER_ENV_SCRIPT"
          voice_changer_activate "$(voice_changer_root)"
        '';
        runScript = "bash";
      };
      command =
        name:
        pkgs.writeShellScriptBin "voice-changer-${name}" ''
          export VOICE_CHANGER_SOURCE=${application}
          exec ${runtime}/bin/voice-changer-env ${./nix/runtime.sh} ${name} "$@"
        '';
      commands = {
        voice-changer = command "start";
        setup = command "setup";
        doctor = command "doctor";
        lock = command "lock";
      };
    in
    {
      packages.${system} = commands // {
        inherit runtime;
        default = pkgs.symlinkJoin {
          name = "voice-changer";
          paths = builtins.attrValues commands;
          meta.mainProgram = "voice-changer-start";
        };
      };
      apps.${system} = pkgs.lib.mapAttrs (name: package: {
        type = "app";
        meta.description = "voice-changer ${name} in the pinned legacy runtime";
        program = pkgs.lib.getExe package;
      }) (commands // { default = commands.voice-changer; });
      devShells.${system}.default = runtime.env;
      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
