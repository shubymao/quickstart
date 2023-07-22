#!/usr/bin/env bash

which -s brew
if [[ $? != 0 ]] ; then
  echo "Home brew not installed"
  echo "Installing home brew by running \n /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else 
  echo "Home brew installed, continue to next step"
fi

echo "Installing ansible from home brew by running brew install ansible"
brew install ansible
