{ pkgs, config, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.grub = {
    enable = true;
  };

  networking.hostName = "pnode1";

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE3YxxVgLik6ci8AD2hhEh832HD5y+3dPBUsd2vgJyad pscale01@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPGO7Bn/RrFKVI4KNnqoZvFK69/IzrR0MhuHEUiepXxV pscal@Adelle"
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  time.timeZone = "America/Los_Angeles";

  swapDevices = [{ device = "/var/lib/swapfile"; size = 4096; }]; # 4 GB

  environment.systemPackages = with pkgs; [
    neovim
    htop
    tmux
    ncdu
    jdk25
    clojure
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Don't change! Read about it here: https://nixos.wiki/wiki/State_Versions
  system.stateVersion = "25.11";

  # ╭──────────────────────────────────────────────────────────╮
  # │                     SOPS-NIX SETUP                       │
  # ╰──────────────────────────────────────────────────────────╯

  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.keyFile = "/etc/ssh/sops-age-key.txt";

  # Example of how to reference a secret:
  # sops.secrets.anki_password = { mode = "0400"; owner = "root"; };

  # ╭──────────────────────────────────────────────────────────╮
  # │                         GIT                              │
  # ╰──────────────────────────────────────────────────────────╯

  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      advice.defaultBranchName = false;
    };
  };

  # ╭──────────────────────────────────────────────────────────╮
  # │                        NGINX                             │
  # ╰──────────────────────────────────────────────────────────╯

  security.acme = {
    acceptTerms = true;
    defaults.email = "me@zzt64.com";
  };

  services.nginx = {
    enable = true;
    enableReload = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;

    commonHttpConfig = ''
      gzip on;
      gzip_proxied any;
      gzip_comp_level 5;
      gzip_types
        application/atom+xml
        application/javascript
        application/json
        application/xml
        application/xml+rss
        application/wasm
        image/svg+xml
        text/css
        text/javascript
        text/plain
        text/xml;
      gzip_vary on;
    '';
  };

  services.nginx.virtualHosts."test.zzt64.com" = {
    forceSSL = true;
    enableACME = true;

    locations = {
      "/" = {
        root = pkgs.writeTextDir "index.html" (builtins.readFile ./index.html);
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
