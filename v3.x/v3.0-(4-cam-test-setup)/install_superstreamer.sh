#!/bin/bash
set -e

echo "===================================================="
echo " SUPER STREAMER MULTI-CAM (Pi3B+ SAFE)"
echo "===================================================="

ARCH=$(dpkg --print-architecture)
if [[ "$ARCH" != "armhf" && "$ARCH" != "arm64" ]]; then
    echo "[ERR] ARM only (Raspberry Pi)"
    exit 1
fi

MAX_CAMS=4

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
# MediaMTX
#################################################
echo "[INFO] Installing MediaMTX..."
URL="https://github.com/bluenviron/mediamtx/releases/download/v1.15.4/mediamtx_v1.15.4_linux_arm64.tar.gz"
TMP="/tmp/mediamtx.tar.gz"

wget -O "$TMP" "$URL"
tar -xzf "$TMP" -C /tmp
sudo mv /tmp/mediamtx /usr/local/bin/
sudo chmod +x /usr/local/bin/mediamtx

#################################################
# Detect USB Cameras (reboot-proof)
#################################################
echo "[INFO] Detecting USB webcams..."
mapfile -t CAMS < <(ls /dev/v4l/by-id/*video* 2>/dev/null | head -n $MAX_CAMS)

if [[ "${#CAMS[@]}" -eq 0 ]]; then
    echo "[WARN] No USB cameras detected."
fi

#################################################
# MediaMTX config (multiple paths)
#################################################
sudo tee /etc/mediamtx.yml >/dev/null <<EOF
api: yes
apiAddress: 127.0.0.1:9997
paths:
EOF

for i in "${!CAMS[@]}"; do
    IDX=$((i+1))
    echo "  usb$IDX:" | sudo tee -a /etc/mediamtx.yml >/dev/null
    echo "    source: publisher" | sudo tee -a /etc/mediamtx.yml >/dev/null
done

#################################################
# Super Streamer Script (CORE LOGIC PRESERVED)
#################################################
sudo tee /usr/local/bin/super_streamer.sh >/dev/null <<'EOF'
#!/bin/bash

DEVICE="$1"
PATH_NAME="$2"

/usr/local/bin/mediamtx /etc/mediamtx.yml >/tmp/mediamtx.log 2>&1 &
sleep 2

echo "[SuperStreamer] Streaming $DEVICE -> $PATH_NAME"

while true; do
    if [[ -e "$DEVICE" ]]; then
        ffmpeg -hide_banner -loglevel error \
            -f v4l2 -input_format yuyv422 -video_size 640x480 -framerate 15 \
            -i "$DEVICE" \
            -vf format=yuv420p \
            -c:v libx264 -preset ultrafast -tune zerolatency \
            -f rtsp "rtsp://localhost:8554/$PATH_NAME"
    else
        echo "[SuperStreamer] $DEVICE missing, retrying..."
        sleep 2
    fi
done
EOF

sudo chmod +x /usr/local/bin/super_streamer.sh

#################################################
# systemd services (one per camera)
#################################################
for i in "${!CAMS[@]}"; do
    IDX=$((i+1))
    CAM="${CAMS[$i]}"

    sudo tee /etc/systemd/system/super-streamer-usb$IDX.service >/dev/null <<EOF
[Unit]
Description=USB RTSP Streamer usb$IDX
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/super_streamer.sh $CAM usb$IDX
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
done

#################################################
# GUI (MINIMAL CHANGE: MULTI STREAM TABLE)
#################################################
sudo mkdir -p /opt/usbstreamer-gui/templates

sudo tee /opt/usbstreamer-gui/app.py >/dev/null <<'EOF'
from flask import Flask, jsonify, render_template, request
import subprocess, json

app = Flask(__name__)

MTX_API = "http://127.0.0.1:9997/v3/paths/list"

def sh(cmd):
    try:
        return subprocess.check_output(cmd, shell=True).decode().strip()
    except:
        return "n/a"

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/status")
def status():
    return jsonify({
        "cpu": sh("top -bn1 | awk '/Cpu/ {print $2+$4\"%\"}'"),
        "ram": sh("free -m | awk '/Mem:/ {print $3\"/\"$2\" MB\"}'"),
        "temp": sh("vcgencmd measure_temp | cut -d= -f2"),
        "uptime": sh("uptime -p")
    })

@app.route("/api/streams")
def streams():
    try:
        data = json.loads(subprocess.check_output(["curl","-s",MTX_API]))
        return jsonify(data["items"])
    except:
        return jsonify([])

@app.route("/api/control", methods=["POST"])
def control():
    cam = request.json["cam"]
    act = request.json["action"]
    subprocess.call(["systemctl", act, f"super-streamer-{cam}.service"])
    return jsonify(ok=True)

app.run(host="0.0.0.0", port=9000)
EOF

sudo tee /opt/usbstreamer-gui/templates/index.html >/dev/null <<'EOF'
<!DOCTYPE html>
<html>
<head>
<script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-900 text-gray-100 p-6">

<h1 class="text-xl mb-4">USB RTSP Streams</h1>

<div id="stats" class="mb-4 text-sm"></div>

<table class="w-full text-sm border">
<thead>
<tr><th>Stream</th><th>Status</th><th>Control</th></tr>
</thead>
<tbody id="rows"></tbody>
</table>

<script>
async function refresh(){
  let s=await fetch('/api/status').then(r=>r.json());
  document.getElementById('stats').innerText =
    `CPU ${s.cpu} | RAM ${s.ram} | TEMP ${s.temp} | ${s.uptime}`;

  let r=await fetch('/api/streams').then(r=>r.json());
  let h='';
  r.forEach(p=>{
    let ok=p.ready?'🟢 LIVE':'🔴 DOWN';
    h+=`<tr><td>${p.name}</td><td>${ok}</td>
    <td>
      <button onclick="cmd('${p.name}','start')">Start</button>
      <button onclick="cmd('${p.name}','stop')">Stop</button>
      <button onclick="cmd('${p.name}','restart')">Restart</button>
    </td></tr>`;
  });
  document.getElementById('rows').innerHTML=h;
}

async function cmd(c,a){
 await fetch('/api/control',{method:'POST',
  headers:{'Content-Type':'application/json'},
  body:JSON.stringify({cam:c,action:a})});
 setTimeout(refresh,1000);
}

setInterval(refresh,5000);
refresh();
</script>
</body>
</html>
EOF

sudo tee /etc/systemd/system/usbstreamer-gui.service >/dev/null <<EOF
[Service]
ExecStart=/usr/bin/python3 /opt/usbstreamer-gui/app.py
Restart=always
EOF

#################################################
# Enable services
#################################################
sudo systemctl daemon-reload

for i in "${!CAMS[@]}"; do
    sudo systemctl enable super-streamer-usb$((i+1))
    sudo systemctl start  super-streamer-usb$((i+1))
done

sudo systemctl enable usbstreamer-gui
sudo systemctl start  usbstreamer-gui

echo "===================================================="
echo " INSTALL COMPLETE"
echo " GUI  : http://<IP>:9000"
echo " RTSP : rtsp://<IP>:8554/usbX"
echo "===================================================="
