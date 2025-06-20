#!/bin/bash

if wmctrl -lx | grep -i "brave-browser.Brave-browser"; then
  wmctrl -xa brave-browser.Brave-browser
else
  brave-browser &
fi
