xrandr --output $display_right --mode 2560x1440 --pos 2560x0 --rotate normal --output $display_left --mode 2560x1440 --pos 0x0 --rotate normal
xrdb -merge ~/.Xresources
~/keymap.sh
exec i3
