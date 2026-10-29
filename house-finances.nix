# House Finances (https://github.com/patreeceeo/house-finances): a Streamlit
# app behind nginx, which asks for a username and password and tells the app
# who signed in.
#
# The app's code is a git checkout in /var/lib/house-finances/app, updated by
# GitHub Actions on each push to main: the deploy key may only run
# house-finances-update with a commit hash. This file defines everything
# else: users, the service, monthly backups and the web server.
{ pkgs, lib, config, ... }:

let
  domain = "house-finances.zzt64.com";
  repoUrl = "https://github.com/patreeceeo/house-finances.git";
  stateDir = "/var/lib/house-finances";
  appDir = "${stateDir}/app";
  backupDir = "${stateDir}/backups";
  port = "8501";

  # Usernames (from the nginx password file) who can change data; everyone
  # else who can sign in can only look.
  editors = [ "patrick" ];

  # Public half of the key GitHub Actions deploys with (DEPLOY_SSH_KEY).
  deployKey = "";

  appEnv = {
    HOUSEFIN_DB = "${stateDir}/finances.db";
    HOUSEFIN_AUTH = "nginx";
    HOUSEFIN_EDITORS = lib.concatStringsSep "," editors;
    HOME = stateDir;
    # uv uses nixpkgs' Python instead of downloading one; PyPI wheels with
    # compiled code (numpy, pyarrow) find the C++ runtime and zlib here.
    UV_PYTHON = "${pkgs.python313}/bin/python3";
    UV_PYTHON_DOWNLOADS = "never";
    LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];
  };
  envArgs = lib.escapeShellArgs (lib.mapAttrsToList (k: v: "${k}=${v}") appEnv);

  update = pkgs.writeShellApplication {
    name = "house-finances-update";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.git pkgs.systemd pkgs.util-linux ];
    text = ''
      if [[ $# -ne 1 || ! "$1" =~ ^[0-9a-f]{40}$ ]]; then
        echo "usage: house-finances-update <full commit hash>" >&2
        exit 2
      fi
      sha="$1"
      as_app() { runuser -u housefin -- env HOME=${stateDir} "$@"; }

      if [[ ! -d ${appDir}/.git ]]; then
        as_app git clone --quiet ${repoUrl} ${appDir}
      fi
      cd ${appDir}
      as_app git fetch --quiet origin
      if ! as_app git cat-file -e "$sha^{commit}"; then
        echo "unknown commit $sha" >&2
        exit 1
      fi
      echo "Updating $(as_app git rev-parse --short HEAD) -> $(echo "$sha" | cut -c1-7)"

      # Back up first: the new code may migrate the database.
      systemctl start house-finances-backup.service
      as_app git checkout --quiet --detach "$sha"
      systemctl restart house-finances.service  # its start runs uv sync

      for _ in $(seq 60); do
        if curl -fsS http://127.0.0.1:${port}/_stcore/health >/dev/null 2>&1; then
          echo "Deployed $(echo "$sha" | cut -c1-7)."
          exit 0
        fi
        sleep 1
      done
      echo "The app did not answer within 60 s; see: journalctl -u house-finances -n 50" >&2
      exit 1
    '';
  };

  # Import bank CSVs over SSH: house-finances-ingest /tmp/export.csv
  ingest = pkgs.writeShellApplication {
    name = "house-finances-ingest";
    runtimeInputs = [ pkgs.util-linux ];
    text = ''
      cd ${appDir}
      exec runuser -u housefin -- env ${envArgs} .venv/bin/python ingest.py "$@"
    '';
  };
in
{
  users.users.housefin = {
    isSystemUser = true;
    group = "housefin";
    home = stateDir;
  };
  users.groups.housefin = { };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 housefin housefin -"
    "d ${backupDir} 0750 housefin housefin -"
  ];

  systemd.services.house-finances = {
    description = "House Finances (Streamlit)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = appEnv;
    # Nothing to run until the first deploy has checked the code out.
    unitConfig.ConditionPathExists = "${appDir}/app.py";
    serviceConfig = {
      User = "housefin";
      Group = "housefin";
      WorkingDirectory = appDir;
      ExecStartPre = "${pkgs.uv}/bin/uv sync --frozen --no-dev --quiet";
      ExecStart = lib.concatStringsSep " " [
        "${appDir}/.venv/bin/streamlit run app.py"
        "--server.address 127.0.0.1 --server.port ${port}"
        "--server.headless true --browser.gatherUsageStats false"
      ];
      TimeoutStartSec = "5min"; # the first uv sync downloads the dependencies
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ stateDir ];
    };
  };

  # A consistent copy of the database (SQLite's .backup, never a half-written
  # file), checked and compressed. Monthly, and before every deploy; copies
  # older than a year are deleted.
  systemd.services.house-finances-backup = {
    description = "Back up the House Finances database";
    startAt = "*-*-01 03:30:00"; # the 1st of each month
    path = [ pkgs.coreutils pkgs.findutils pkgs.gzip pkgs.sqlite ];
    serviceConfig = {
      Type = "oneshot";
      User = "housefin";
      Group = "housefin";
    };
    script = ''
      db=${appEnv.HOUSEFIN_DB}
      if [[ ! -f "$db" ]]; then
        echo "No database yet; nothing to back up."
        exit 0
      fi
      out=${backupDir}/finances-$(date +%F-%H%M%S).db
      sqlite3 "$db" ".backup '$out.tmp'"
      check=$(sqlite3 "$out.tmp" "PRAGMA integrity_check")
      if [[ "$check" != ok ]]; then
        echo "Backup failed its integrity check: $check" >&2
        exit 1
      fi
      mv "$out.tmp" "$out"
      gzip "$out"
      find ${backupDir} -name 'finances-*.db.gz' -mtime +365 -delete
      echo "Backed up to $out.gz"
    '';
  };
  # Catch up on a missed monthly run if the server was off on the 1st.
  systemd.timers.house-finances-backup.timerConfig.Persistent = true;

  # GitHub Actions signs in as this user; its key can only run the update.
  users.users.house-finances-deploy = {
    isSystemUser = true;
    group = "house-finances-deploy";
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = lib.optional (deployKey != "")
      ''command="/run/wrappers/bin/sudo ${update}/bin/house-finances-update \"$SSH_ORIGINAL_COMMAND\"",restrict ${deployKey}'';
  };
  users.groups.house-finances-deploy = { };
  security.sudo.extraRules = [{
    users = [ "house-finances-deploy" ];
    commands = [{ command = "${update}/bin/house-finances-update"; options = [ "NOPASSWD" ]; }];
  }];

  environment.systemPackages = [ update ingest ];

  # One line per person, "name:hash" (see the house-finances deploy README).
  sops.secrets.house_finances_htpasswd = { owner = "nginx"; mode = "0400"; };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;
    basicAuthFile = config.sops.secrets.house_finances_htpasswd.path;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${port}";
      proxyWebsockets = true; # Streamlit talks to the browser over a websocket
      extraConfig = ''
        # Who signed in; replaces any X-Remote-User the browser sent.
        proxy_set_header X-Remote-User $remote_user;
        proxy_read_timeout 1d;
        client_max_body_size 20m;
      '';
    };
  };
}
