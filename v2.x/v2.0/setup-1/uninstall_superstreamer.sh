#!/bin/bash

echo "============================================="
echo " SUPER STREAMER + GUI ROLLBACK"
echo "============================================="

sudo systemctl stop super-streamer usbstreamer-gui
sudo systemctl disable super-streamer usbstreamer-gui

sudo rm -f /etc/systemd/system/super-streamer.service
sudo rm -f /etc/systemd/system/usbstreamer-gui.service

sudo systemctl daemon-reload

sudo killall ffmpeg || true
sudo killall mediamtx || true

sudo rm -f /usr/local/bin/super_streamer.sh
sudo rm -f /usr/local/bin/mediamtx
sudo rm -f /etc/mediamtx.yml
sudo rm -rf /opt/usbstreamer-gui

echo "============================================="
echo " ROLLBACK COMPLETE — SYSTEM CLEAN"
echo "============================================="
