
# Shuby Mao's quickstart

Quickly initialize key setup and environment in order to start being productive
## Clone Repo

```
git clone https://github.com/shubymao/quickstart.git
```

To change the https to ssh version (to allow edit and pushing) run
```
git remote set-url origin git@github.com:shubymao/quickstart.git
```


## Inventory Node Setup 
## Control Node Setup
### Install ansible-playbook

```
python3 -m pip install --user ansible
```

### Add ansible to path

```
export PATH=$PATH:/home/{your_user_name}/.local/bin
```
Before you run, you should have make sure you are in your own user (and not root).

To run simply, run
```
ansible-playbook -K --ask-vault-pass universal.yml
```

To run a particular tag use the -t command. E.g
```
ansible-playbook -t nvim universal.yml
```

## SSH Setup (Personal Multi-Server Flow)

This repo now installs only public keys. It does not copy a private key to target machines.

### Option A: use the repo key file

Put your public key in `keys/id_ed25519.pub` (vault-encrypted is fine), then run:

```bash
ansible-playbook -K --ask-vault-pass -t ssh universal.yml
```

### Option B: override key at runtime (recommended for quick bootstrap)

```bash
ansible-playbook -K --ask-vault-pass -t ssh \
  -e "bootstrap_pubkey=$(cat ~/.ssh/id_ed25519.pub)" \
  universal.yml
```

## First-Time Server Bootstrap

Use `server-init.sh` in two phases:

1. Bootstrap user + SSH key (keeps password auth enabled):

```bash
sudo ./server-init.sh
```

2. After confirming key login works, harden SSH:

```bash
sudo ./server-init.sh --harden-ssh
```
