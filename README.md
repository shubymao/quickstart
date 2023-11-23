# quickstart
Quickly initialize key setup and environment in order to start being productive

## Install ansible-playbook
```
python3 -m pip install --user ansible
```

## Add ansible to path
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
