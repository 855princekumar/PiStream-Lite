#!/bin/bash

echo "============================================="
echo " SUPER STREAMER MULTI-CAM ROLLBACK"
echo "============================================="

echo "[INFO] Stopping GUI..."
sudo systemctl stop usbstreamer-gui.service || true
sudo systemctl disable usbstreamer-gui.service || true

echo "[INFO] Stopping stream services..."
for i in 1 2 3 4; do
    sudo systemctl stop super-streamer-usb$i.service || true
    sudo systemctl disable super-streamer-usb$i.service || true
done

echo "[INFO] Removing systemd unit files..."
sudo rm -f /etc/systemd/system/super-streamer-usb*.service
sudo rm -f /etc/systemd/system/usbstreamer-gui.service

echo "[INFO] Reloading systemd..."
sudo systemctl daemon-reload

echo "[INFO] Killing leftover processes..."
sudo killall ffmpeg || true
sudo killall mediamtx || true

echo "[INFO] Removing binaries and configs..."
sudo rm -f /usr/local/bin/super_streamer.sh
sudo rm -f /usr/local/bin/mediamtx
sudo rm -f /etc/mediamtx.yml

echo "[INFO] Removing GUI..."
sudo rm -rf /opt/usbstreamer-gui

echo "============================================="
echo " ROLLBACK COMPLETE — SYSTEM CLEAN"
echo "============================================="
