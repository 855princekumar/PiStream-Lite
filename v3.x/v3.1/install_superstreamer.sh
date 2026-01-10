#!/bin/bash
set -e

echo "===================================================="
echo " SUPER STREAMER v3.1 — SINGLE PAGE AUTH (STABLE)"
echo "===================================================="

#################################################
# Dependencies
#################################################
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
# Detect cameras
#################################################
mapfile -t CAMS < <(ls /dev/v4l/by-id/*video-index0 | head -n 2)
if [[ "${#CAMS[@]}" -ne 2 ]]; then
  echo "[ERR] Exactly 2 USB webcams required"
  exit 1
fi

#################################################
# Config + credentials
#################################################
sudo mkdir -p /etc/usbstreamer
echo -e "RES=640x480\nFPS=15" | sudo tee /etc/usbstreamer/usb1.conf >/dev/null
echo -e "RES=640x480\nFPS=15" | sudo tee /etc/usbstreamer/usb2.conf >/dev/null
echo "admin:admin123" | sudo tee /etc/usbstreamer/credentials.txt >/dev/null
sudo chmod 600 /etc/usbstreamer/credentials.txt

#################################################
# Streamer (UNCHANGED)
#################################################
sudo tee /usr/local/bin/super_streamer.sh >/dev/null <<'EOF'
#!/bin/bash
DEVICE="$1"
NAME="$2"
CONF="/etc/usbstreamer/$NAME.conf"

while true; do
  source "$CONF"
  ffmpeg -hide_banner -loglevel error \
    -f v4l2 -input_format yuyv422 \
    -video_size "$RES" -framerate "$FPS" \
    -i "$DEVICE" \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -threads 1 -b:v 1500k -g 30 \
    -f rtsp "rtsp://localhost:8554/$NAME"
done
EOF

sudo chmod +x /usr/local/bin/super_streamer.sh

#################################################
# Stream services
#################################################
sudo tee /etc/systemd/system/super-streamer-usb1.service >/dev/null <<EOF
[Unit]
After=mediamtx.service
Requires=mediamtx.service

[Service]
ExecStart=/usr/local/bin/super_streamer.sh ${CAMS[0]} usb1
Restart=always

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

[Install]
WantedBy=multi-user.target
EOF

#################################################
# GUI backend — SINGLE PAGE, NO ROUTING
#################################################
sudo mkdir -p /opt/usbstreamer-gui/templates

sudo tee /opt/usbstreamer-gui/app.py >/dev/null <<'EOF'
from flask import Flask, jsonify, render_template, request, session, redirect
import subprocess, json, os

app = Flask(__name__)
app.secret_key = "pistream-lite"

CONF_DIR = "/etc/usbstreamer"
CRED = f"{CONF_DIR}/credentials.txt"

SERVICES = {
    "usb1": "super-streamer-usb1.service",
    "usb2": "super-streamer-usb2.service"
}

MTX_API = "http://127.0.0.1:9997/v3/paths/list"

# ---------------- AUTH ----------------

def authed():
    return session.get("auth") is True

def check_login(u, p):
    cu, cp = open(CRED).read().strip().split(":")
    return u == cu and p == cp

@app.before_request
def auth_guard():
    # FIX: allow index ("/") to bypass auth to avoid redirect loop
    if request.endpoint in ("index", "login", "static"):
        return
    if request.path.startswith("/api/login"):
        return
    if not authed():
        return redirect("/")

# ---------------- PAGES ----------------

@app.route("/")
def index():
    return render_template("index.html")

# ---------------- AUTH API ----------------

@app.route("/api/login", methods=["POST"])
def login():
    data = request.get_json()
    if check_login(data["user"], data["pass"]):
        session["auth"] = True
        return jsonify(ok=True)
    return jsonify(ok=False), 401

@app.route("/api/logout", methods=["POST"])
def logout():
    session.clear()
    return jsonify(ok=True)

@app.route("/api/password", methods=["POST"])
def password():
    new = request.json["pass"]
    with open(CRED, "w") as f:
        f.write(f"admin:{new}")
    session.clear()
    return jsonify(ok=True)

@app.route("/api/reboot", methods=["POST"])
def reboot():
    subprocess.Popen(["reboot"])
    return jsonify(ok=True)

# ---------------- SYSTEM STATUS ----------------

@app.route("/api/status")
def status():
    sh = subprocess.getoutput
    return jsonify(
        cpu=sh("top -bn1 | awk '/Cpu/ {print $2+$4\"%\"}'"),
        ram=sh("free -m | awk '/Mem:/ {print $3\"/\"$2\" MB\"}'"),
        temp=sh("vcgencmd measure_temp | cut -d= -f2"),
        uptime=sh("uptime -p")
    )

# ---------------- STREAM STATUS ----------------

@app.route("/api/stream_check/<name>")
def stream_check(name):
    try:
        data = json.loads(subprocess.getoutput(f"curl -s {MTX_API}"))
        for p in data.get("items", []):
            if p["name"] == name and p["ready"]:
                return jsonify(stream="live")
    except:
        pass
    return jsonify(stream="down")

# ---------------- CONTROL ----------------

@app.route("/api/control", methods=["POST"])
def control():
    cam = request.json["cam"]
    action = request.json["action"]
    subprocess.call(["systemctl", action, SERVICES[cam]])
    return jsonify(ok=True)

# ---------------- RESOLUTION ----------------

@app.route("/api/resolution")
def resolution():
    out = {}
    for cam in ("usb1", "usb2"):
        try:
            with open(f"{CONF_DIR}/{cam}.conf") as f:
                for line in f:
                    if line.startswith("RES="):
                        out[cam] = line.strip().split("=")[1]
        except:
            out[cam] = "640x480"
    return jsonify(out)

@app.route("/api/set_res", methods=["POST"])
def set_res():
    cam = request.json["cam"]
    res = request.json["res"]
    other = "usb2" if cam == "usb1" else "usb1"

    with open(f"{CONF_DIR}/{cam}.conf", "w") as f:
        f.write(f"RES={res}\nFPS=15\n")

    with open(f"{CONF_DIR}/{other}.conf", "w") as f:
        f.write("RES=640x480\nFPS=15\n")

    subprocess.call(["systemctl", "restart", SERVICES[cam]])
    subprocess.call(["systemctl", "restart", SERVICES[other]])

    return jsonify(ok=True)

# ---------------- RUN ----------------

app.run(host="0.0.0.0", port=9000)


EOF

#################################################
# GUI frontend — LOGIN + DASHBOARD SAME PAGE
#################################################
sudo tee /opt/usbstreamer-gui/templates/index.html >/dev/null <<'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>USB RTSP GUI</title>
<link rel="icon" href="data:,">
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

<!-- LOGIN -->
<div id="loginBox" class="bg-gray-800 p-6 rounded-xl w-80 shadow-lg">
  <h2 class="text-lg mb-2 text-center">USB Stream Login</h2>
  <p class="text-xs text-gray-400 mb-4 text-center">
    Default: admin / admin123
  </p>
  <input id="user" class="w-full p-2 mb-3 rounded bg-gray-700" placeholder="Username">
  <input id="pass" type="password" class="w-full p-2 mb-4 rounded bg-gray-700" placeholder="Password">
  <button onclick="login()" class="w-full bg-blue-600 p-2 rounded">Login</button>
</div>

<!-- DASHBOARD -->
<div id="dashboard" class="hidden space-y-6 w-full max-w-3xl">

<!-- PROJECT HEADER -->
<div class="bg-gray-800 p-4 rounded-xl text-center shadow-lg">
  <h1 class="text-xl font-semibold tracking-wide">
    PiStream-Lite <span class="text-blue-400">v3.1</span>
  </h1>
  <h2>Multi-cam-streaming</h2>
  <p class="text-xs text-gray-400 mt-1">
    Lightweight RTSP Streaming & Control Dashboard
  </p>
</div>

<!-- SYSTEM HEALTH -->
<div class="bg-gray-800 p-6 rounded-xl shadow-lg">
  <h1 class="text-xl mb-4">System Health</h1>
  <div class="grid grid-cols-3 gap-4 text-sm">
    <div>CPU: <span id="cpu"></span></div>
    <div>RAM: <span id="ram"></span></div>
    <div>Temp: <span id="temp"></span></div>
    <div>Uptime: <span id="uptime"></span></div>
  </div>

  <div class="mt-4 flex gap-2">
    <button onclick="reboot()" class="bg-red-600 px-4 py-2 rounded">Reboot</button>
    <button onclick="showPasswordBox()" class="bg-yellow-600 px-4 py-2 rounded">Change Password</button>
    <button onclick="logout()" class="bg-gray-600 px-4 py-2 rounded">Logout</button>
  </div>
</div>

<!-- STREAMS -->
<div id="streams" class="space-y-6"></div>
</div>

<!-- PASSWORD POPUP -->
<div id="pwdBox" class="hidden fixed inset-0 bg-black/60 flex items-center justify-center">
  <div class="bg-gray-800 p-6 rounded-xl w-80">
    <h2 class="text-lg mb-4">Change Password</h2>
    <input id="newpass" type="password" class="w-full p-2 mb-3 rounded bg-gray-700" placeholder="New password">
    <input id="confpass" type="password" class="w-full p-2 mb-4 rounded bg-gray-700" placeholder="Confirm password">
    <div class="flex gap-2">
      <button onclick="savePassword()" class="bg-green-600 px-4 py-2 rounded w-full">Save</button>
      <button onclick="hidePasswordBox()" class="bg-gray-600 px-4 py-2 rounded w-full">Cancel</button>
    </div>
  </div>
</div>

<script>
const cams = ["usb1","usb2"];

function login(){
  fetch("/api/login",{
    method:"POST",
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({
      user: user.value,
      pass: pass.value
    })
  }).then(r=>{
    if(r.ok){
      loginBox.classList.add("hidden");
      dashboard.classList.remove("hidden");
      init();
    } else {
      alert("Invalid credentials");
    }
  });
}

function logout(){
  fetch("/api/logout",{method:"POST"}).then(()=>location.reload());
}

function reboot(){
  fetch("/api/reboot",{method:"POST"});
}

function showPasswordBox(){ pwdBox.classList.remove("hidden"); }
function hidePasswordBox(){ pwdBox.classList.add("hidden"); }

function savePassword(){
  if(newpass.value !== confpass.value){
    alert("Passwords do not match");
    return;
  }
  fetch("/api/password",{
    method:"POST",
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({pass:newpass.value})
  }).then(()=>{
    alert("Password updated. Please login again.");
    location.reload();
  });
}

function streamBlock(name){
return `
<div class="bg-gray-800 p-6 rounded-xl shadow-lg">
  <h2 class="text-lg mb-2">${name.toUpperCase()}</h2>

  <div class="text-sm mb-3">
    Resolution:
    <span id="${name}-res" class="font-semibold text-green-400">
      480p (STABLE)
    </span>
  </div>

  <div class="flex items-center gap-2 mb-4">
    <span id="${name}-dot" class="w-3 h-3 rounded-full bg-yellow-400 pulse"></span>
    <span id="${name}-text">CHECKING</span>
  </div>

  <div class="flex gap-2 mb-4">
    <button onclick="cmd('${name}','start')" class="bg-green-600 px-4 py-2 rounded">Start</button>
    <button onclick="cmd('${name}','stop')" class="bg-red-600 px-4 py-2 rounded">Stop</button>
    <button onclick="cmd('${name}','restart')" class="bg-yellow-500 px-4 py-2 rounded">Restart</button>
  </div>

  <div class="flex gap-2">
    <button id="${name}-720"
      onclick="setRes('${name}','1280x720')"
      class="px-4 py-1 rounded text-sm bg-gray-600">
      720p
    </button>
    <button id="${name}-480"
      onclick="setRes('${name}','640x480')"
      class="px-4 py-1 rounded text-sm bg-green-600 text-white">
      480p
    </button>
  </div>
</div>`;
}

function init(){
  streams.innerHTML = cams.map(streamBlock).join("");
  setInterval(refresh,5000);
  setInterval(()=>cams.forEach(check),8000);
  setInterval(syncResUI,4000);
  refresh();
  cams.forEach(check);
  syncResUI();
}

function refresh(){
  fetch("/api/status").then(r=>r.json()).then(d=>{
    cpu.innerText=d.cpu;
    ram.innerText=d.ram;
    temp.innerText=d.temp;
    uptime.innerText=d.uptime;
  });
}

function check(c){
  fetch(`/api/stream_check/${c}`).then(r=>r.json()).then(d=>{
    const dot=document.getElementById(c+"-dot");
    const txt=document.getElementById(c+"-text");
    if(d.stream==="live"){
      dot.className="w-3 h-3 rounded-full bg-green-400 pulse";
      txt.innerText="LIVE";
    } else {
      dot.className="w-3 h-3 rounded-full bg-red-500 pulse";
      txt.innerText="DOWN";
    }
  });
}

function cmd(c,a){
  fetch("/api/control",{
    method:"POST",
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({cam:c,action:a})
  });
}

function setRes(c,r){
  fetch("/api/set_res",{
    method:"POST",
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({cam:c,res:r})
  });
}

function syncResUI(){
  fetch('/api/resolution').then(r=>r.json()).then(res=>{
    cams.forEach(c=>{
      const label=document.getElementById(c+"-res");
      const b720=document.getElementById(c+"-720");
      const b480=document.getElementById(c+"-480");

      if(res[c]==="1280x720"){
        label.innerText="720p (HIGH)";
        label.className="font-semibold text-blue-400";
        b720.className="px-4 py-1 rounded text-sm bg-blue-600 text-white";
        b480.className="px-4 py-1 rounded text-sm bg-gray-700";
      }else{
        label.innerText="480p (STABLE)";
        label.className="font-semibold text-green-400";
        b720.className="px-4 py-1 rounded text-sm bg-gray-600";
        b480.className="px-4 py-1 rounded text-sm bg-green-600 text-white";
      }
    });
  });
}
</script>
</body>
</html>

EOF

#################################################
# GUI service
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
echo " GUI  : http://<IP>:9000"
echo " USER : admin"
echo " PASS : admin123"
echo "===================================================="
