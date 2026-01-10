#!/bin/bash

echo "===================================================="
echo " PiStream-Lite 2.1 - SINGLE CAM + GUI + AUTH + RES"
echo "===================================================="

echo "[INFO] Stopping services..."
sudo systemctl stop super-streamer usbstreamer-gui mediamtx 2>/dev/null || true
sudo systemctl disable super-streamer usbstreamer-gui mediamtx 2>/dev/null || true

echo "[INFO] Removing systemd service files..."
sudo rm -f /etc/systemd/system/super-streamer.service
sudo rm -f /etc/systemd/system/usbstreamer-gui.service
sudo rm -f /etc/systemd/system/mediamtx.service

echo "[INFO] Reloading systemd..."
sudo systemctl daemon-reload
sudo systemctl reset-failed

echo "[INFO] Killing leftover processes..."
sudo pkill -f ffmpeg || true
sudo pkill -f mediamtx || true
sudo pkill -f usbstreamer || true

echo "[INFO] Removing binaries..."
sudo rm -f /usr/local/bin/super_streamer.sh
sudo rm -f /usr/local/bin/mediamtx

echo "[INFO] Removing configuration files..."
sudo rm -rf /etc/usbstreamer
sudo rm -f /etc/mediamtx.yml

echo "[INFO] Removing GUI files..."
sudo rm -rf /opt/usbstreamer-gui

echo "[INFO] Cleanup complete."

echo "============================================="
echo " UNINSTALL COMPLETE — SYSTEM RESTORED"
echo "============================================="
