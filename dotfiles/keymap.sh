#!/bin/sh

sleep 5
echo "pkill"
pkill -9 xcape
echo "layhout "
setxkbmap -layout us
echo "no cap"
setxkbmap -option ctrl:nocaps
echo "xcape 1"
xcape -e 'control_l=escape'
