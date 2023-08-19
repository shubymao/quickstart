#!/usr/bin/bash

setxkbmap -layout us
setxkbmap -option ctrl:nocaps
xcape -e 'Control_L=Escape'
xmodmap -e "remove mod4 = Hyper_L"
xmodmap -e "add mod1 = Hyper_L"
xmodmap -e "keycode 65 = Hyper_L"
xmodmap -e "keycode any = space"
xcape -e "Hyper_L=space"
