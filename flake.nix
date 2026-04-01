{
  description = "pnode1";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, disko, sops-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      nixosConfigurations.racknerd-pnode1 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { };
        modules = [
          disko.nixosModules.disko
          ./disk-config.nix
          ./configuration.nix
          ./hardware-configuration.nix
          sops-nix.nixosModules.sops
        ];
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.age
          pkgs.cowsay
          pkgs.jq
          pkgs.nixos-anywhere
          pkgs.sops
          pkgs.nixos-rebuild
        ];

        TARGET_IP = "23.94.214.130";

        shellHook = ''
          PS1="\[\e[00;34m\]λ \W \[\e[0m\]"
          cowsay -e '^^' -f small -W 72 "Welcome to pnode1 dev shell."
          echo ""

          if [[ -f dev.json ]]; then
            export ED25519_ROOT_SECRET_PATH="$(jq -r '.ed25519_root_secret_path' dev.json)"
            export ED25519_ROOT_PUBLIC_PATH="$(jq -r '.ed25519_root_public_path // ""' dev.json)"

            # Export Git identity.
            export GIT_NAME="$(jq -r '.git_name' dev.json)"
            export GIT_EMAIL="$(jq -r '.git_email' dev.json)"

            export NIX_SSHOPTS="-i $ED25519_ROOT_SECRET_PATH"

            echo "SSH key loaded from dev.json"
            echo "   Secret: $ED25519_ROOT_SECRET_PATH"
            echo "Git identity: $GIT_NAME <$GIT_EMAIL>"
          else
            echo "Error: dev.json not found!"
            echo "   Run: cp dev.conf.json dev.json && \$EDITOR dev.json"
            echo ""
            echo "exiting nix develop shell..."
            exit 1
          fi

          alias ssh-root="ssh -i $ED25519_ROOT_SECRET_PATH root@$TARGET_IP"

          alias rebuild-local='nixos-rebuild switch --flake .#racknerd-pnode1 \
              --target-host root@$TARGET_IP --fast'

          alias rebuild-remote='nixos-rebuild switch --flake .#racknerd-pnode1 \
              --target-host root@$TARGET_IP --build-host root@$TARGET_IP --fast'

          alias rebuild='rebuild-local'

          alias deploy___careful_will_wipe='nixos-anywhere \
              --generate-hardware-config nixos-generate-config ./hardware-configuration.nix \
              --flake .#racknerd-pnode1 root@$TARGET_IP'

          alias push-age-key='scp age-server-key.txt root@$TARGET_IP:/etc/ssh/sops-age-key.txt && \
                              ssh root@$TARGET_IP chmod 400 /etc/ssh/sops-age-key.txt && \
                              echo "age key pushed and permissions fixed"'

          alias push-gitolite='./sh/push-gitolite.sh'
          alias rsync="./sh/rsync.sh"
        '';
      };
    };
}
