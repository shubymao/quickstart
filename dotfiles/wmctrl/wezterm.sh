#!/bin/bash

if wmctrl -lx | grep -i "org.wezfurlong.wezterm.org.wezfurlong.wezterm"; then
  wmctrl -xa org.wezfurlong.wezterm.org.wezfurlong.wezterm
else
  wezterm &
fi
