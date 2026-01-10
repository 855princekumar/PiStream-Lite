#!/bin/bash

echo "============================================="
echo " UNINSTALLING SUPER STREAMER v3.1 (SINGLE PAGE GUI)"
echo "============================================="

echo "[INFO] Stopping services..."
sudo systemctl stop \
  usbstreamer-gui \
  super-streamer-usb1 \
  super-streamer-usb2 \
  mediamtx 2>/dev/null || true

echo "[INFO] Disabling services..."
sudo systemctl disable \
  usbstreamer-gui \
  super-streamer-usb1 \
  super-streamer-usb2 \
  mediamtx 2>/dev/null || true

echo "[INFO] Removing systemd unit files..."
sudo rm -f /etc/systemd/system/usbstreamer-gui.service
sudo rm -f /etc/systemd/system/super-streamer-usb1.service
sudo rm -f /etc/systemd/system/super-streamer-usb2.service
sudo rm -f /etc/systemd/system/mediamtx.service

echo "[INFO] Reloading systemd..."
sudo systemctl daemon-reload

echo "[INFO] Killing running processes..."
sudo pkill -f ffmpeg || true
sudo pkill -f mediamtx || true
sudo pkill -f usbstreamer-gui || true

echo "[INFO] Removing installed files..."
sudo rm -rf /opt/usbstreamer-gui
sudo rm -rf /etc/usbstreamer
sudo rm -f /usr/local/bin/super_streamer.sh
sudo rm -f /usr/local/bin/mediamtx
sudo rm -f /etc/mediamtx.yml

echo "============================================="
echo " UNINSTALL COMPLETE — SYSTEM CLEAN"
echo "============================================="
