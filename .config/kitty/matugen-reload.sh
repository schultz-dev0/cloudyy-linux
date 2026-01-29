#!/bin/sh
ln -sfS $HOME/dots/.config/matugen/generated/kitty-colors.conf $HOME/dots/.config/kitty/kitty-colors.conf
pkill -SIGUSR1 kitty || true
