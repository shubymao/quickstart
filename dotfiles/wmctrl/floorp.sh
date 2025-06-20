#!/bin/bash

if wmctrl -lx | grep -i "Navigator.floorp"; then
  wmctrl -xa Navigator.floorp
else
  floorp &
fi
