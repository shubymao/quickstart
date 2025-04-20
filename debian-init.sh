#!/usr/bin/env bash

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Not running as root please run script with sudo."
    exit
fi

sudo apt update && sudo apt upgrade

if ! command -v ansible 2>&1 >/dev/null
then
    echo "Ansible could not be found. Attempting to installing"
    echo "Installation guide from https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html#installing-ansible-on-debian"
    export UBUNTU_CODENAME=jammy
    wget -O- "https://keyserver.ubuntu.com/pks/lookup?fingerprint=on&op=get&search=0x6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367" | sudo gpg --dearmour -o /usr/share/keyrings/ansible-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/ansible-archive-keyring.gpg] http://ppa.launchpad.net/ansible/ansible/ubuntu $UBUNTU_CODENAME main" | sudo tee /etc/apt/sources.list.d/ansible.list
    sudo apt update && sudo apt install ansible
else 
    echo "Ansible Install. Please Follow the Read me and run ansible playbook"
fi
echo "Installation script finished."
