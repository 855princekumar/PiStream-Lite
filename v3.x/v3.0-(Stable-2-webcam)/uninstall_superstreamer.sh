#!/bin/bash

echo "============================================="
echo " SUPER STREAMER 3.0-CAM UNINSTALL"
echo "============================================="

sudo systemctl stop super-streamer-usb1 super-streamer-usb2 usbstreamer-gui mediamtx || true
sudo systemctl disable super-streamer-usb1 super-streamer-usb2 usbstreamer-gui mediamtx || true

sudo rm -f /etc/systemd/system/super-streamer-usb*.service
sudo rm -f /etc/systemd/system/usbstreamer-gui.service
sudo rm -f /etc/systemd/system/mediamtx.service

sudo systemctl daemon-reload

sudo killall ffmpeg || true
sudo killall mediamtx || true

sudo rm -f /usr/local/bin/super_streamer.sh
sudo rm -f /usr/local/bin/mediamtx
sudo rm -f /etc/mediamtx.yml
sudo rm -rf /opt/usbstreamer-gui
sudo rm -rf /etc/usbstreamer

echo "============================================="
echo " UNINSTALL COMPLETE — SYSTEM CLEAN"
echo "============================================="
