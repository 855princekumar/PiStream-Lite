#!/bin/bash

echo "============================================="
echo " SUPER STREAMER ROLLBACK (Verbose Mode)"
echo "============================================="

echo "[INFO] Stopping services..."

# Stop services (will show errors if not found)
sudo systemctl stop super-streamer.service
sudo systemctl stop mediamtx
sudo systemctl stop rtsp-webcam
sudo systemctl stop rtsp-server

echo "[INFO] Disabling services..."

# Disable services
sudo systemctl disable super-streamer.service
sudo systemctl disable mediamtx
sudo systemctl disable rtsp-webcam
sudo systemctl disable rtsp-server

echo "[INFO] Removing systemd service files..."

# Remove unit files (will show errors for missing files)
sudo rm /etc/systemd/system/super-streamer.service
sudo rm /etc/systemd/system/mediamtx.service
sudo rm /etc/systemd/system/rtsp-webcam.service
sudo rm /etc/systemd/system/rtsp-server.service

echo "[INFO] Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "[INFO] Killing any leftover FFmpeg or MediaMTX processes..."
# Will show error if process not running
sudo killall ffmpeg
sudo killall mediamtx

echo "[INFO] Removing MediaMTX binary (if present)..."
sudo rm /usr/local/bin/mediamtx

echo "[INFO] Removing MediaMTX config file..."
sudo rm /etc/mediamtx.yml

echo "[INFO] Rollback completed."
echo "============================================="
echo " SUPER STREAMER HAS BEEN REMOVED COMPLETELY"
echo "============================================="

