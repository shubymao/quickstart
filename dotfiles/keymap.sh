#!/bin/sh

sleep 5
echo "pkill"
pkill -9 xcape
echo "layhout "
setxkbmap -layout us
echo "no cap"
setxkbmap -option ctrl:nocaps
echo "xcape 1"
xcape -e 'Control_L=Escape'
echo "remove mod4 hyper l"
xmodmap -e "remove mod4 = Hyper_L"
echo "mod 1 add hyper l"
xmodmap -e "add mod1 = Hyper_L"
echo "key 65 as hyper l"
xmodmap -e "keycode 65 = Hyper_L"
echo "any key as space"
xmodmap -e "keycode any = space"
echo "hyper l = space xcape"
xcape -e "Hyper_L=space"
