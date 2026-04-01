# pnode1

A cool name for my latest personal server configuration.

## First deployment (full install from ISO)

```bash
nix develop
deploy___careful_will_wipe
```

## One-time setup (secrets + keys)

```bash
cd pnode1
nix develop

# 1. Generate a permanent age keypair for the server
age-keygen -o age-server-key.txt
# → Copy the public key line, example:
# Public key: age1k02jmszaud77khkg6qlpdemtkyy7scs4gkr2ylxcdyvm8dztfedsgykeaa

# 2. Create .sops.yaml with both recipients
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: secrets\.yaml$
    age:
      - age1k02jmszaud77khkg6qlpdemtkyy7scs4gkr2ylxcdyvm8dztfedsgykeaa   # ← replace with age public key (generated above)
      - ssh-ed25519 AAAAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx yume@kei   # ← replace with your SSH public key
EOF

# 3. Create/edit secrets
sops secrets.yaml
# If you are just re-deploying the server (i.e. secrets.yaml already exists),
# run `sops updatekeys secrets.yaml`

# 4. Push the server’s age private key
push-age-key     # ← scp + chmod in one shot (see alias definition in flake.nix)
rm age-server-key.txt   # never commit private keys!

git add .sops.yaml secrets.yaml
git commit -m "add encrypted secrets + permanent server age key"
git push
```

### Gitolite Admin Setup

All Gitolite configuration lives in `gitolite/admin/`:

- `conf/gitolite.conf` – repo definitions, permissions, groups
- `keydir/*.pub` – user SSH public keys (filename = username)

Edit these files directly in the repository as needed.

To apply changes to the server:

```bash
nix develop
push-gitolite   # syncs local admin config → server
```

The script clones the remote `gitolite-admin.git` repository temporarily, rsyncs your local changes (overwriting the clone), commits, and force-pushes. Changes are applied instantly on the server (new repos are created, permissions updated, keys added/removed).


## Daily use

```bash
nix develop

rebuild-local   # build on local machine → fastest for big changes
rebuild-remote  # build directly on server → smallest transfer

# Edit secrets anytime
sops secrets.yaml   # ← (locally: uses ssh key from .sops.yaml)
git commit -am "update secrets"
git push
rebuild-local
```
