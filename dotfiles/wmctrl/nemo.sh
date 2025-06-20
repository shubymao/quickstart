#!/bin/bash

if wmctrl -lx | grep -i "nemo.Nemo"; then
  wmctrl -xa nemo.Nemo
else
  nemo &
  disown
fi
