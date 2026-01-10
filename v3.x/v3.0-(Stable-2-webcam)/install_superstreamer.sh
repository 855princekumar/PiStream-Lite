#!/bin/bash
set -e

echo "===================================================="
echo " SUPER STREAMER v3.0 — 2 CAM + GUI + BALANCED 720P"
echo "===================================================="

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
# MediaMTX (DEDICATED SERVICE)
#################################################
echo "[INFO] Installing MediaMTX..."
URL="https://github.com/bluenviron/mediamtx/releases/download/v1.15.4/mediamtx_v1.15.4_linux_arm64.tar.gz"
TMP="/tmp/mediamtx.tar.gz"

wget -qO "$TMP" "$URL"
tar -xzf "$TMP" -C /tmp
sudo mv /tmp/mediamtx /usr/local/bin/
sudo chmod +x /usr/local/bin/mediamtx

sudo tee /etc/mediamtx.yml >/dev/null <<EOF
api: yes
apiAddress: 127.0.0.1:9997

paths:
  usb1: { source: publisher }
  usb2: { source: publisher }
EOF

sudo tee /etc/systemd/system/mediamtx.service >/dev/null <<EOF
[Unit]
Description=MediaMTX RTSP Server
After=network.target

[Service]
ExecStart=/usr/local/bin/mediamtx /etc/mediamtx.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

#################################################
# Detect REAL camera nodes only
#################################################
echo "[INFO] Detecting USB webcams..."
mapfile -t CAMS < <(
  ls /dev/v4l/by-id/*video-index0 2>/dev/null | head -n 2
)

if [[ "${#CAMS[@]}" -ne 2 ]]; then
  echo "[ERR] Exactly 2 USB webcams required."
  ls -l /dev/v4l/by-id/
  exit 1
fi

#################################################
# Per-camera resolution config
#################################################
sudo mkdir -p /etc/usbstreamer
echo -e "RES=640x480\nFPS=15" | sudo tee /etc/usbstreamer/usb1.conf >/dev/null
echo -e "RES=640x480\nFPS=15" | sudo tee /etc/usbstreamer/usb2.conf >/dev/null

#################################################
# Streamer script (UNCHANGED PIPELINE)
#################################################
sudo tee /usr/local/bin/super_streamer.sh >/dev/null <<'EOF'
#!/bin/bash

DEVICE="$1"
NAME="$2"
CONF="/etc/usbstreamer/$NAME.conf"

while true; do
    source "$CONF"

    ffmpeg -hide_banner -loglevel error \
        -f v4l2 \
        -input_format yuyv422 \
        -video_size "$RES" \
        -framerate "$FPS" \
        -i "$DEVICE" \
        -c:v libx264 \
        -preset ultrafast \
        -tune zerolatency \
        -threads 1 \
        -b:v 1500k \
        -maxrate 1500k \
        -bufsize 3000k \
        -g 30 \
        -f rtsp "rtsp://localhost:8554/$NAME"
done
EOF

sudo chmod +x /usr/local/bin/super_streamer.sh

#################################################
# systemd services (INDEPENDENT)
#################################################
sudo tee /etc/systemd/system/super-streamer-usb1.service >/dev/null <<EOF
[Unit]
After=mediamtx.service
Requires=mediamtx.service

[Service]
ExecStart=/usr/local/bin/super_streamer.sh ${CAMS[0]} usb1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/super-streamer-usb2.service >/dev/null <<EOF
[Unit]
After=mediamtx.service
Requires=mediamtx.service

[Service]
ExecStart=/usr/local/bin/super_streamer.sh ${CAMS[1]} usb2
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

#################################################
# GUI BACKEND (RESOLUTION STATE + BALANCE)
#################################################
sudo mkdir -p /opt/usbstreamer-gui/templates

sudo tee /opt/usbstreamer-gui/app.py >/dev/null <<'EOF'
from flask import Flask, jsonify, render_template, request
import subprocess, json, os

app = Flask(__name__)

SERVICES = {
    "usb1": "super-streamer-usb1.service",
    "usb2": "super-streamer-usb2.service"
}
CONF_DIR = "/etc/usbstreamer"
MTX_API = "http://127.0.0.1:9997/v3/paths/list"

def sh(cmd):
    try:
        return subprocess.check_output(cmd, shell=True).decode().strip()
    except:
        return "n/a"

def read_res(cam):
    try:
        with open(f"{CONF_DIR}/{cam}.conf") as f:
            for line in f:
                if line.startswith("RES="):
                    return line.strip().split("=")[1]
    except:
        pass
    return "640x480"

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
        "uptime": sh("uptime -p")
    })

@app.route("/api/stream_check/<name>")
def stream_check(name):
    try:
        data = json.loads(subprocess.check_output(["curl","-s",MTX_API]))
        for p in data.get("items", []):
            if p["name"] == name and p["ready"]:
                return jsonify({"stream": "live"})
        return jsonify({"stream": "down"})
    except:
        return jsonify({"stream": "down"})

@app.route("/api/control", methods=["POST"])
def control():
    cam = request.json.get("cam")
    action = request.json.get("action")
    subprocess.call(["systemctl", action, SERVICES[cam]])
    return jsonify({"ok": True})

@app.route("/api/set_res", methods=["POST"])
def set_res():
    cam = request.json["cam"]
    res = request.json["res"]
    other = "usb2" if cam == "usb1" else "usb1"

    with open(f"{CONF_DIR}/{cam}.conf","w") as f:
        f.write(f"RES={res}\nFPS=15\n")
    with open(f"{CONF_DIR}/{other}.conf","w") as f:
        f.write("RES=640x480\nFPS=15\n")

    subprocess.call(["systemctl","restart",SERVICES[cam]])
    subprocess.call(["systemctl","restart",SERVICES[other]])
    return jsonify(ok=True)

@app.route("/api/resolution")
def resolution():
    return jsonify({
        "usb1": read_res("usb1"),
        "usb2": read_res("usb2")
    })

app.run(host="0.0.0.0", port=9000)
EOF

#################################################
# GUI FRONTEND — SAME UI + VISUAL HIGHLIGHT
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
.pulse { animation: pulse 1.5s infinite; }
</style>
</head>

<body class="bg-gray-900 text-gray-100 min-h-screen flex items-center justify-center">
<div class="space-y-6 w-full max-w-3xl">

<!-- PROJECT HEADER -->
  <div class="bg-gray-800 p-6 rounded-xl shadow-lg">
    <h1 class="text-xl font-semibold tracking-wide">
      PiStream-Lite <span class="text-blue-400">v3.0</span>
    </h1>
    <p class="text-xs text-gray-400 mt-1">
      Lightweight RTSP Streaming & Control Dashboard
    </p>
  </div>

<div class="bg-gray-800 p-6 rounded-xl shadow-lg">
  <h1 class="text-xl mb-4">System Health</h1>
  <div class="grid grid-cols-3 gap-4 text-sm">
    <div>CPU: <span id="cpu"></span></div>
    <div>RAM: <span id="ram"></span></div>
    <div>Temp: <span id="temp"></span></div>
    <div>Throttled: <span id="throttled"></span></div>
    <div>Uptime: <span id="uptime"></span></div>
  </div>
</div>

<script>
function block(name){
return `
<div class="bg-gray-800 p-6 rounded-xl shadow-lg">
  <h2 class="text-lg mb-4">${name.toUpperCase()}</h2>

  <div class="flex items-center gap-2 mb-4">
    <span id="${name}-dot" class="w-3 h-3 rounded-full bg-yellow-400 pulse"></span>
    <span id="${name}-text" class="text-sm text-yellow-400">CHECKING</span>
  </div>

  <div class="flex justify-center gap-2 mb-4">
    <button onclick="cmd('${name}','start')" class="bg-green-600 px-4 py-2 rounded">Start</button>
    <button onclick="cmd('${name}','stop')" class="bg-red-600 px-4 py-2 rounded">Stop</button>
    <button onclick="cmd('${name}','restart')" class="bg-yellow-500 px-4 py-2 rounded text-black">Restart</button>
  </div>

  <div class="flex justify-center gap-2">
    <button id="${name}-720" onclick="setRes('${name}','1280x720')" class="px-4 py-1 rounded text-sm bg-gray-600">720p</button>
    <button id="${name}-480" onclick="setRes('${name}','640x480')" class="px-4 py-1 rounded text-sm bg-gray-600">480p</button>
  </div>
</div>`;
}
</script>

<div id="streams" class="space-y-6"></div>
</div>

<script>
const cams=["usb1","usb2"];
document.getElementById("streams").innerHTML=cams.map(block).join("");

async function refresh(){
  const d=await fetch('/api/status').then(r=>r.json());
  for(k in d){const e=document.getElementById(k);if(e)e.innerText=d[k];}
}

async function check(c){
  const d=await fetch(`/api/stream_check/${c}`).then(r=>r.json());
  const dot=document.getElementById(c+"-dot");
  const txt=document.getElementById(c+"-text");
  if(d.stream==="live"){
    dot.className="w-3 h-3 rounded-full bg-green-400 pulse";
    txt.innerText="LIVE"; txt.className="text-sm text-green-400";
  }else{
    dot.className="w-3 h-3 rounded-full bg-red-500 pulse";
    txt.innerText="DOWN"; txt.className="text-sm text-red-500";
  }
}

async function syncResolutionUI(){
  const res = await fetch('/api/resolution').then(r=>r.json());
  cams.forEach(cam=>{
    const b720=document.getElementById(cam+"-720");
    const b480=document.getElementById(cam+"-480");
    if(res[cam]==="1280x720"){
      b720.className="px-4 py-1 rounded text-sm bg-blue-600 text-white";
      b480.className="px-4 py-1 rounded text-sm bg-gray-700";
    }else{
      b720.className="px-4 py-1 rounded text-sm bg-gray-600";
      b480.className="px-4 py-1 rounded text-sm bg-green-600 text-white";
    }
  });
}

async function cmd(c,a){
  await fetch('/api/control',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({cam:c,action:a})});
  setTimeout(()=>check(c),1000);
}

async function setRes(c,r){
  await fetch('/api/set_res',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({cam:c,res:r})});
  setTimeout(()=>{
    syncResolutionUI();
    cams.forEach(check);
  },1500);
}

setInterval(refresh,5000);
setInterval(()=>cams.forEach(check),10000);
setInterval(syncResolutionUI,5000);

refresh();
cams.forEach(check);
syncResolutionUI();
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
sudo systemctl daemon-reload
sudo systemctl enable mediamtx super-streamer-usb1 super-streamer-usb2 usbstreamer-gui
sudo systemctl restart mediamtx super-streamer-usb1 super-streamer-usb2 usbstreamer-gui

echo "===================================================="
echo " INSTALL COMPLETE"
echo " RTSP : rtsp://<IP>:8554/usb1"
echo " RTSP : rtsp://<IP>:8554/usb2"
echo " GUI  : http://<IP>:9000"
echo "===================================================="
