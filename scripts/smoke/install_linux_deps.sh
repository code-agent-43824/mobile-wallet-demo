#!/usr/bin/env bash
# Packages a Linux runner needs to build the desktop app and to run it
# headless for the smoke stage (display, session bus, keyring, screenshots).
set -euo pipefail
sudo apt-get update -qq
sudo apt-get install -y -qq \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev libsecret-1-dev liblzma-dev libstdc++-12-dev \
  xvfb x11-utils dbus-x11 gnome-keyring imagemagick
