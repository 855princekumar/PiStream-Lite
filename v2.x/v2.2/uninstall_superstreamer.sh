#!/bin/bash
set -e

echo "===================================================="
echo " PiStream-Lite 2.2 - SINGLE CAM + GUI + AUTH + RES"
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
sudo pkill -f super_streamer || true
sudo pkill -f usbstreamer || true
sudo pkill -f flask || true

echo "[INFO] Removing binaries..."
sudo rm -f /usr/local/bin/super_streamer.sh
sudo rm -f /usr/local/bin/mediamtx

echo "[INFO] Removing configuration files..."
sudo rm -rf /etc/usbstreamer
sudo rm -f /etc/mediamtx.yml

echo "[INFO] Removing GUI application..."
sudo rm -rf /opt/usbstreamer-gui

echo "[INFO] Cleaning temporary files..."
sudo rm -f /tmp/mediamtx.log
sudo rm -f /tmp/mediamtx.tar.gz

echo "============================================="
echo " UNINSTALL COMPLETE — SYSTEM CLEAN"
echo "============================================="
echo " ✔ Streams stopped"
echo " ✔ GUI removed"
echo " ✔ MediaMTX removed"
echo " ✔ Credentials removed"
echo " ✔ Safe to reinstall or upgrade"
echo "============================================="
