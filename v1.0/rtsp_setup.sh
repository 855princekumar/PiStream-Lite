#!/bin/bash

echo "============================================="
echo "     SUPER STREAMER v3.2 (One-Service RTSP)"
echo "============================================="

ARCH=$(dpkg --print-architecture)
echo "[INFO] System Architecture: $ARCH"

if [[ "$ARCH" != "arm64" ]]; then
    echo "[ERR] This script supports ONLY ARM64 Raspberry Pi OS."
    exit 1
fi

echo "[INFO] Installing dependencies..."
sudo apt update
sudo apt install -y ffmpeg v4l-utils wget tar

echo "[INFO] Downloading MediaMTX Release..."
URL="https://github.com/bluenviron/mediamtx/releases/download/v1.15.4/mediamtx_v1.15.4_linux_arm64.tar.gz"
TMP="/tmp/mediamtx.tar.gz"

wget -O "$TMP" "$URL"
if [[ $? -ne 0 ]]; then
    echo "[ERR] Could not download MediaMTX!"
    exit 1
fi

echo "[INFO] Extracting MediaMTX..."
tar -xzf "$TMP" -C /tmp
sudo mv /tmp/mediamtx /usr/local/bin/
sudo chmod +x /usr/local/bin/mediamtx

echo "[INFO] Writing MediaMTX configuration..."
sudo tee /etc/mediamtx.yml >/dev/null <<EOF
paths:
  usb:
    source: publisher
EOF

echo "[INFO] Creating unified streamer script..."
sudo tee /usr/local/bin/super_streamer.sh >/dev/null <<'EOF'
#!/bin/bash

# Start MediaMTX first
/usr/local/bin/mediamtx /etc/mediamtx.yml >/tmp/mediamtx.log 2>&1 &
sleep 2

echo "[SuperStreamer] Waiting for webcam..."

while true; do
    if [[ -e /dev/video0 ]]; then
        echo "[SuperStreamer] Webcam detected, starting stream..."

        ffmpeg -hide_banner -loglevel error \
            -f v4l2 -input_format yuyv422 -video_size 640x480 -framerate 30 \
            -i /dev/video0 \
            -vf "format=yuv420p" \
            -c:v libx264 -preset ultrafast -tune zerolatency \
            -f rtsp rtsp://localhost:8554/usb
    else
        echo "[SuperStreamer] Webcam not found, retrying..."
        sleep 2
    fi
done
EOF

sudo chmod +x /usr/local/bin/super_streamer.sh

echo "[INFO] Creating systemd service..."
sudo tee /etc/systemd/system/super-streamer.service >/dev/null <<EOF
[Unit]
Description=Unified Auto-Heal RTSP Webcam Streamer
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/super_streamer.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "[INFO] Enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable super-streamer
sudo systemctl restart super-streamer

echo
echo "==============================================="
echo " SUPER STREAMER v3.2 INSTALLED AND RUNNING"
echo " RTSP URL: rtsp://<PI-IP>:8554/usb"
echo " Auto-start: YES"
echo " Auto-restart: YES"
echo " Auto-heal: YES"
echo "==============================================="

