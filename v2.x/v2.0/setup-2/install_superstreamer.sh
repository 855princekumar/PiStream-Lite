#!/bin/bash
set -e

echo "===================================================="
echo " SUPER STREAMER v2.0 + GUI + STREAM HEALTH (MediaMTX)"
echo "===================================================="

ARCH=$(dpkg --print-architecture)
if [[ "$ARCH" != "arm64" ]]; then
    echo "[ERR] ARM64 only (Raspberry Pi OS)"
    exit 1
fi

echo "[INFO] Installing dependencies..."
sudo apt update
sudo apt install -y \
    ffmpeg \
    v4l-utils \
    wget \
    tar \
    python3 \
    python3-flask \
    curl

#################################################
# MediaMTX (with API enabled)
#################################################
echo "[INFO] Installing MediaMTX..."
URL="https://github.com/bluenviron/mediamtx/releases/download/v1.15.4/mediamtx_v1.15.4_linux_arm64.tar.gz"
TMP="/tmp/mediamtx.tar.gz"

wget -O "$TMP" "$URL"
tar -xzf "$TMP" -C /tmp
sudo mv /tmp/mediamtx /usr/local/bin/
sudo chmod +x /usr/local/bin/mediamtx

sudo tee /etc/mediamtx.yml >/dev/null <<EOF
api: yes
apiAddress: 127.0.0.1:9997

paths:
  usb:
    source: publisher
EOF

#################################################
# Super Streamer (UNCHANGED CORE)
#################################################
echo "[INFO] Installing Super Streamer..."
sudo tee /usr/local/bin/super_streamer.sh >/dev/null <<'EOF'
#!/bin/bash

/usr/local/bin/mediamtx /etc/mediamtx.yml >/tmp/mediamtx.log 2>&1 &
sleep 2

echo "[SuperStreamer] Waiting for webcam..."

while true; do
    if [[ -e /dev/video0 ]]; then
        echo "[SuperStreamer] Webcam detected, starting stream..."
        ffmpeg -hide_banner -loglevel error \
            -f v4l2 -input_format yuyv422 -video_size 640x480 -framerate 30 \
            -i /dev/video0 \
            -vf format=yuv420p \
            -c:v libx264 -preset ultrafast -tune zerolatency \
            -f rtsp rtsp://localhost:8554/usb
    else
        echo "[SuperStreamer] Webcam not found, retrying..."
        sleep 2
    fi
done
EOF

sudo chmod +x /usr/local/bin/super_streamer.sh

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

#################################################
# GUI BACKEND (MediaMTX API health check)
#################################################
echo "[INFO] Installing GUI..."
sudo mkdir -p /opt/usbstreamer-gui/templates

sudo tee /opt/usbstreamer-gui/app.py >/dev/null <<'EOF'
from flask import Flask, jsonify, render_template, request
import subprocess
import json

app = Flask(__name__)

SERVICE = "super-streamer.service"
MTX_API = "http://127.0.0.1:9997/v3/paths/list"

def sh(cmd):
    try:
        return subprocess.check_output(
            cmd, shell=True, stderr=subprocess.DEVNULL
        ).decode().strip()
    except subprocess.CalledProcessError:
        return "inactive"

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/status")
def status():
    return jsonify({
        "cpu": sh("top -bn1 | awk '/Cpu/ {print $2+$4\"%\"}'"),
        "ram": sh("free -m | awk '/Mem:/ {print $3\"/\"$2\" MB\"}'"),
        "temp": sh("vcgencmd measure_temp | cut -d= -f2"),
        "throttled": sh("vcgencmd get_throttled | cut -d= -f2"),
        "uptime": sh("uptime -p"),
        "state": sh(f"systemctl is-active {SERVICE}")
    })

@app.route("/api/stream_check")
def stream_check():
    try:
        raw = subprocess.check_output(
            ["curl", "-s", MTX_API],
            timeout=2
        ).decode()

        data = json.loads(raw)
        for path in data.get("items", []):
            if path.get("name") == "usb" and path.get("ready") is True:
                return jsonify({"stream": "live"})

        return jsonify({"stream": "down"})
    except Exception:
        return jsonify({"stream": "down"})

@app.route("/api/control", methods=["POST"])
def control():
    action = request.json.get("action")
    if action not in ["start", "stop", "restart"]:
        return jsonify({"error": "invalid"}), 400
    subprocess.call(["systemctl", action, SERVICE])
    return jsonify({"ok": True})

app.run(host="0.0.0.0", port=9000)
EOF

#################################################
# GUI FRONTEND (animated health indicator)
#################################################
sudo tee /opt/usbstreamer-gui/templates/index.html >/dev/null <<'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>USB RTSP GUI</title>
<script src="https://cdn.tailwindcss.com"></script>

<style>
@keyframes pulse {
  0% { opacity: 0.3; }
  50% { opacity: 1; }
  100% { opacity: 0.3; }
}
.pulse {
  animation: pulse 1.5s infinite;
}
</style>
</head>

<body class="bg-gray-900 text-gray-100 min-h-screen">

<!-- PAGE CONTAINER -->
<div class="mx-auto max-w-3xl px-4 py-10 space-y-6">

  <!-- PROJECT HEADER -->
  <div class="bg-gray-800 p-6 rounded-xl shadow-lg">
    <h1 class="text-xl font-semibold tracking-wide">
      PiStream-Lite <span class="text-blue-400">v2.0</span>
    </h1>
    <p class="text-xs text-gray-400 mt-1">
      Lightweight RTSP Streaming & Control Dashboard
    </p>
  </div>

  <!-- STREAM CONTROL -->
  <div class="bg-gray-800 p-6 rounded-xl shadow-lg">

    <h1 class="text-xl mb-4">USB RTSP Stream Control</h1>

    <div class="grid grid-cols-3 gap-4 text-sm mb-6">
      <div>CPU: <span id="cpu"></span></div>
      <div>RAM: <span id="ram"></span></div>
      <div>Temp: <span id="temp"></span></div>
      <div>Throttled: <span id="throttled"></span></div>
      <div>Uptime: <span id="uptime"></span></div>
      <div>Status: <span id="state"></span></div>
    </div>

    <div class="flex items-center gap-2 mb-6">
      <span id="dot" class="w-3 h-3 rounded-full bg-yellow-400 pulse"></span>
      <span id="streamText" class="text-sm text-yellow-400">CHECKING</span>
    </div>

    <div class="flex justify-center gap-4">
      <button onclick="cmd('start')" class="bg-green-600 px-6 py-2 rounded">Start</button>
      <button onclick="cmd('stop')" class="bg-red-600 px-6 py-2 rounded">Stop</button>
      <button onclick="cmd('restart')" class="bg-yellow-500 px-6 py-2 rounded text-black">Restart</button>
    </div>

  </div>

</div>

<script>
async function refresh(){
  const r = await fetch('/api/status');
  const d = await r.json();
  for (k in d) {
    const el = document.getElementById(k);
    if (el) el.innerText = d[k];
  }
}

async function checkStream(){
  const dot = document.getElementById("dot");
  const text = document.getElementById("streamText");

  try{
    const r = await fetch('/api/stream_check');
    const d = await r.json();

    if(d.stream === "live"){
      dot.className = "w-3 h-3 rounded-full bg-green-400 pulse";
      text.innerText = "LIVE";
      text.className = "text-sm text-green-400";
    } else {
      dot.className = "w-3 h-3 rounded-full bg-red-500 pulse";
      text.innerText = "DOWN";
      text.className = "text-sm text-red-500";
    }
  }catch{
    dot.className = "w-3 h-3 rounded-full bg-gray-500";
    text.innerText = "ERROR";
  }
}

async function cmd(a){
  await fetch('/api/control',{
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({action:a})
  });
  setTimeout(() => {
    refresh();
    checkStream();
  }, 1000);
}

setInterval(refresh, 5000);
setInterval(checkStream, 10000);

refresh();
checkStream();
</script>

</body>
</html>
EOF

#################################################
# GUI systemd
#################################################
sudo tee /etc/systemd/system/usbstreamer-gui.service >/dev/null <<EOF
[Unit]
Description=USB RTSP GUI
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/usbstreamer-gui/app.py
WorkingDirectory=/opt/usbstreamer-gui
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

#################################################
# Enable services
#################################################
echo "[INFO] Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable super-streamer usbstreamer-gui
sudo systemctl restart super-streamer usbstreamer-gui

echo "===================================================="
echo " INSTALL COMPLETE"
echo " RTSP : rtsp://<IP>:8554/usb"
echo " GUI  : http://<IP>:9000"
echo " Health source: MediaMTX API (publisher-ready)"
echo "===================================================="
