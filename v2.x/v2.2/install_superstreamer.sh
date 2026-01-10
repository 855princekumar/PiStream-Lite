#!/bin/bash
set -e

echo "===================================================="
echo " PiStream-Lite 2.2 - SINGLE CAM + GUI + AUTH + RES"
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
  usb:
    source: publisher
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
# Config + Credentials
#################################################
sudo mkdir -p /etc/usbstreamer
echo -e "RES=640x480\nFPS=15" | sudo tee /etc/usbstreamer/usb.conf >/dev/null
echo "admin:admin123" | sudo tee /etc/usbstreamer/credentials.txt >/dev/null
sudo chmod 600 /etc/usbstreamer/credentials.txt

#################################################
# Streamer (CORE LOGIC UNCHANGED)
#################################################
sudo tee /usr/local/bin/super_streamer.sh >/dev/null <<'EOF'
#!/bin/bash

CONF="/etc/usbstreamer/usb.conf"

while true; do
  source "$CONF"

  if [[ -e /dev/video0 ]]; then
    ffmpeg -hide_banner -loglevel error \
      -f v4l2 \
      -input_format yuyv422 \
      -video_size "$RES" \
      -framerate "$FPS" \
      -i /dev/video0 \
      -c:v libx264 \
      -preset ultrafast \
      -tune zerolatency \
      -threads 1 \
      -b:v 2500k \
      -maxrate 2500k \
      -bufsize 5000k \
      -g 30 \
      -f rtsp rtsp://localhost:8554/usb
  else
    sleep 2
  fi
done
EOF

sudo chmod +x /usr/local/bin/super_streamer.sh

#################################################
# systemd Stream Service
#################################################
sudo tee /etc/systemd/system/super-streamer.service >/dev/null <<EOF
[Unit]
After=mediamtx.service
Requires=mediamtx.service

[Service]
ExecStart=/usr/local/bin/super_streamer.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

#################################################
# GUI Backend
#################################################
sudo mkdir -p /opt/usbstreamer-gui/templates

sudo tee /opt/usbstreamer-gui/app.py >/dev/null <<'EOF'
from flask import Flask, jsonify, render_template, request, session
import subprocess, json, os

app = Flask(__name__)
app.secret_key = "pistream-lite"

# ---------------- FILE PATHS ----------------

CONF = "/etc/usbstreamer/usb.conf"
CRED = "/etc/usbstreamer/credentials.txt"
SERVICE = "super-streamer.service"

MTX_API = "http://127.0.0.1:9997/v3/paths/list"
MTX_CFG = "/etc/mediamtx.yml"
RTSP_STATE = "/etc/usbstreamer/rtsp_auth.json"

# ---------------- HELPERS ----------------

def sh(cmd):
    return subprocess.getoutput(cmd)

def check_login(u, p):
    cu, cp = open(CRED).read().strip().split(":")
    return u == cu and p == cp

# ---------------- RTSP AUTH HANDLER ----------------

def update_rtsp_auth(user=None, passwd=None):
    with open(MTX_CFG) as f:
        lines = f.readlines()

    out = []
    in_usb = False

    for line in lines:
        if line.strip() == "usb:":
            in_usb = True
            out.append(line)
            continue

        if in_usb and line.startswith("  "):
            if line.strip().startswith(("readUser:", "readPass:")):
                continue
            out.append(line)
        else:
            in_usb = False
            out.append(line)

    if user and passwd:
        for i, l in enumerate(out):
            if l.strip() == "usb:":
                out.insert(i + 1, f"    readUser: {user}\n")
                out.insert(i + 2, f"    readPass: {passwd}\n")
                break

    with open(MTX_CFG, "w") as f:
        f.writelines(out)

    # CRITICAL: reload, not restart (prevents camera reset)
    subprocess.call(["systemctl", "reload", "mediamtx"])

# ---------------- ROUTES ----------------

@app.route("/")
def index():
    return render_template("index.html")

# -------- AUTH --------

@app.route("/api/login", methods=["POST"])
def login():
    d = request.json
    if check_login(d["user"], d["pass"]):
        session["auth"] = True
        return jsonify(ok=True)
    return jsonify(ok=False), 401

@app.route("/api/logout", methods=["POST"])
def logout():
    session.clear()
    return jsonify(ok=True)

@app.route("/api/password", methods=["POST"])
def password():
    with open(CRED, "w") as f:
        f.write("admin:" + request.json["pass"])
    session.clear()
    return jsonify(ok=True)

# -------- SYSTEM --------

@app.route("/api/reboot", methods=["POST"])
def reboot():
    subprocess.Popen(["reboot"])
    return jsonify(ok=True)

@app.route("/api/status")
def status():
    return jsonify(
        cpu=sh("top -bn1 | awk '/Cpu/ {print $2+$4\"%\"}'"),
        ram=sh("free -m | awk '/Mem:/ {print $3\"/\"$2\" MB\"}'"),
        temp=sh("vcgencmd measure_temp | cut -d= -f2"),
        uptime=sh("uptime -p")
    )

# -------- STREAM HEALTH --------

@app.route("/api/stream_check")
def stream_check():
    try:
        data = json.loads(sh(f"curl -s {MTX_API}"))
        for p in data.get("items", []):
            if p.get("name") == "usb" and p.get("ready"):
                return jsonify(stream="live")
    except:
        pass
    return jsonify(stream="down")

# -------- STREAM CONTROL --------

@app.route("/api/control", methods=["POST"])
def control():
    subprocess.call(["systemctl", request.json["action"], SERVICE])
    return jsonify(ok=True)

# -------- RESOLUTION --------

@app.route("/api/resolution")
def resolution():
    for line in open(CONF):
        if line.startswith("RES="):
            return jsonify(res=line.strip().split("=")[1])
    return jsonify(res="640x480")

@app.route("/api/set_res", methods=["POST"])
def set_res():
    with open(CONF, "w") as f:
        f.write(f"RES={request.json['res']}\nFPS=15\n")
    subprocess.call(["systemctl", "restart", SERVICE])
    return jsonify(ok=True)

# -------- RTSP URL --------

@app.route("/api/rtsp_url")
def rtsp_url():
    ip = sh("hostname -I | awk '{print $1}'")

    if os.path.exists(RTSP_STATE):
        data = json.load(open(RTSP_STATE))
        if data.get("enabled"):
            return jsonify(
                url=f"rtsp://{data['user']}:{data['pass']}@{ip}:8554/usb",
                auth=True
            )

    return jsonify(url=f"rtsp://{ip}:8554/usb", auth=False)

# -------- RTSP AUTH API --------

@app.route("/api/rtsp_auth", methods=["POST"])
def rtsp_auth():
    user = request.json.get("user")
    passwd = request.json.get("pass")

    if user and passwd:
        update_rtsp_auth(user, passwd)
        with open(RTSP_STATE, "w") as f:
            json.dump({"enabled": True, "user": user, "pass": passwd}, f)
    else:
        update_rtsp_auth()
        if os.path.exists(RTSP_STATE):
            os.remove(RTSP_STATE)

    return jsonify(ok=True)

# ---------------- RUN ----------------

app.run(host="0.0.0.0", port=9000)


EOF

#################################################
# GUI Frontend
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
<div id="login" class="bg-gray-800 p-6 rounded-xl w-80">
  <p class="text-center text-sm mb-4 text-gray-400">
    Default: <b>admin / admin123</b>
  </p>
  <input id="u" class="w-full p-2 mb-2 bg-gray-700 rounded" placeholder="Username">
  <input id="p" type="password" class="w-full p-2 mb-4 bg-gray-700 rounded" placeholder="Password">
  <button onclick="login()" class="w-full bg-blue-600 p-2 rounded">Login</button>
</div>

<!-- DASHBOARD -->
<div id="dash" class="hidden w-full max-w-xl space-y-6">

<!-- PROJECT HEADER -->
<div class="bg-gray-800 p-4 rounded-xl text-center shadow-lg">
  <h1 class="text-xl font-semibold tracking-wide">
    PiStream-Lite <span class="text-blue-400">v2.2</span>
  </h1>
  <p class="text-xs text-gray-400 mt-1">
    Lightweight RTSP Streaming & Control Dashboard
  </p>
</div>

<!-- SYSTEM HEALTH -->
<div class="bg-gray-800 p-6 rounded-xl">
  <div>CPU: <span id="cpu"></span></div>
  <div>RAM: <span id="ram"></span></div>
  <div>Temp: <span id="temp"></span></div>
  <div>Uptime: <span id="uptime"></span></div>
</div>

<!-- STREAM STATUS -->
<div class="bg-gray-800 p-6 rounded-xl">
  <div class="flex items-center gap-2 mb-3">
    <span id="dot" class="w-3 h-3 rounded-full bg-yellow-400 pulse"></span>
    <span id="streamText" class="text-sm text-yellow-400">CHECKING</span>
  </div>

  <div class="mb-2">
    Resolution: <span id="res" class="font-bold"></span>
  </div>

  <div class="flex gap-2 mb-4">
    <button onclick="setRes('640x480')" class="bg-green-600 px-4 py-1 rounded">480p</button>
    <button onclick="setRes('1280x720')" class="bg-blue-600 px-4 py-1 rounded">720p</button>
    <button onclick="setRes('1920x1080')" class="bg-red-600 px-4 py-1 rounded">1080p</button>
  </div>

  <div class="flex gap-2">
    <button onclick="cmd('start')" class="bg-green-700 px-4 py-2 rounded">Start</button>
    <button onclick="cmd('stop')" class="bg-red-700 px-4 py-2 rounded">Stop</button>
    <button onclick="cmd('restart')" class="bg-yellow-600 px-4 py-2 rounded">Restart</button>
  </div>
</div>

<!-- RTSP ACCESS -->
<div class="bg-gray-800 p-6 rounded-xl">
<p id="rtspAuthState" class="text-xs text-gray-400 mb-2">
  Auth: Checking…
</p>

  <h3 class="text-sm mb-3 text-gray-300">RTSP Access</h3>
  
  <div class="text-xs mb-3 break-all bg-gray-900 p-2 rounded">
    <span id="rtspUrl">Loading…</span>
    <button onclick="copyRTSP()"
      class="ml-2 text-blue-400 underline">Copy</button>
  </div>

  <div class="grid grid-cols-2 gap-2 mb-3">
    <input id="rtspUser"
      class="p-2 bg-gray-700 rounded text-sm"
      placeholder="RTSP Username">

    <input id="rtspPass"
      type="password"
      class="p-2 bg-gray-700 rounded text-sm"
      placeholder="RTSP Password">
  </div>

  <div class="flex gap-2">
    <button onclick="setRTSPAuth()"
      class="bg-blue-600 px-3 py-1 rounded text-sm">
      Apply
    </button>
    <button onclick="clearRTSPAuth()"
      class="bg-gray-600 px-3 py-1 rounded text-sm">
      Disable Auth
    </button>
  </div>
</div>

<!-- ACTIONS -->
<div class="flex gap-2 justify-center">
  <button onclick="reboot()" class="bg-red-600 px-4 py-2 rounded">Reboot</button>
  <button onclick="chg()" class="bg-yellow-600 px-4 py-2 rounded">Change Password</button>
  <button onclick="logout()" class="bg-gray-600 px-4 py-2 rounded">Logout</button>
</div>

</div>

<!-- CHANGE PASSWORD MODAL -->
<div id="pwdBox" class="hidden fixed inset-0 bg-black bg-opacity-60 flex items-center justify-center z-50">
  <div class="bg-gray-800 p-6 rounded-xl w-80 shadow-lg">
    <h2 class="text-lg mb-4 text-center">Change Password</h2>

    <input id="newpass" type="password"
      class="w-full p-2 mb-3 bg-gray-700 rounded"
      placeholder="New password">

    <input id="confpass" type="password"
      class="w-full p-2 mb-4 bg-gray-700 rounded"
      placeholder="Confirm password">

    <div class="flex justify-between">
      <button onclick="hidePasswordBox()" class="bg-gray-600 px-4 py-2 rounded">
        Cancel
      </button>
      <button onclick="savePassword()" class="bg-blue-600 px-4 py-2 rounded">
        Save
      </button>
    </div>
  </div>
</div>

<script>
/* ---------- LOGIN ---------- */

function login(){
  fetch("/api/login",{
    method:"POST",
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({
      user: document.getElementById("u").value,
      pass: document.getElementById("p").value
    })
  })
  .then(r=>{
    if(!r.ok){ alert("Invalid credentials"); return; }
    document.getElementById("login").style.display="none";
    document.getElementById("dash").classList.remove("hidden");
    init();
  });
}

function logout(){
  fetch("/api/logout",{method:"POST"}).then(()=>location.reload());
}

/* ---------- SYSTEM ---------- */

function reboot(){ fetch("/api/reboot",{method:"POST"}); }

function cmd(a){
  fetch("/api/control",{
    method:"POST",
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({action:a})
  });
}

function setRes(r){
  fetch("/api/set_res",{
    method:"POST",
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({res:r})
  });
}

/* ---------- INIT ---------- */

function init(){
  refresh();
  syncRes();
  checkStream();
  loadRTSP();   // <-- ADD THIS LINE

  setInterval(refresh,5000);
  setInterval(syncRes,3000);
  setInterval(checkStream,8000);
}

/* ---------- STATUS ---------- */

function refresh(){
  fetch("/api/status").then(r=>r.json()).then(d=>{
    cpu.innerText=d.cpu;
    ram.innerText=d.ram;
    temp.innerText=d.temp;
    uptime.innerText=d.uptime;
  });
}

function checkStream(){
  fetch("/api/stream_check").then(r=>r.json()).then(d=>{
    if(d.stream==="live"){
      dot.className="w-3 h-3 rounded-full bg-green-400 pulse";
      streamText.innerText="LIVE";
      streamText.className="text-sm text-green-400";
    }else{
      dot.className="w-3 h-3 rounded-full bg-red-500 pulse";
      streamText.innerText="DOWN";
      streamText.className="text-sm text-red-500";
    }
  });
}

function syncRes(){
  fetch("/api/resolution").then(r=>r.json()).then(d=>{
    res.innerText=d.res;
  });
}

/* ---------- PASSWORD ---------- */

function chg(){ pwdBox.classList.remove("hidden"); }
function hidePasswordBox(){ pwdBox.classList.add("hidden"); }

function savePassword(){
  const np=newpass.value, cp=confpass.value;
  if(!np||!cp) return alert("Password cannot be empty");
  if(np!==cp) return alert("Passwords do not match");

  fetch("/api/password",{
    method:"POST",
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({pass:np})
  }).then(()=>{
    alert("Password updated. Please login again.");
    location.reload();
  });
}

/* ================================
   RTSP URL + AUTH MANAGEMENT
   ================================ */

function loadRTSP(){
  fetch("/api/rtsp_url")
    .then(r => r.json())
    .then(d => {
      rtspUrl.innerText = d.url;
      rtspAuthState.innerText = d.auth
        ? "Auth: Enabled"
        : "Auth: Disabled";
    });
}

function copyRTSP(){
  const el = document.getElementById("rtspUrl");
  if(!el) return;

  navigator.clipboard.writeText(el.innerText).then(() => {
    const btn = event.target;
    const old = btn.innerText;
    btn.innerText = "Copied ✓";
    btn.classList.add("text-green-400");

    setTimeout(() => {
      btn.innerText = old;
      btn.classList.remove("text-green-400");
    }, 1500);
  });
}

function setRTSPAuth(){
  fetch("/api/rtsp_auth",{
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      user: document.getElementById("rtspUser").value,
      pass: document.getElementById("rtspPass").value
    })
  }).then(() => {
    alert("RTSP authentication updated.\nStream restarting.");
    setTimeout(loadRTSP, 2000);
  });
}

function clearRTSPAuth(){
  fetch("/api/rtsp_auth",{
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ user: "", pass: "" })
  }).then(() => {
    alert("RTSP authentication disabled.");
    setTimeout(loadRTSP, 2000);
  });
}

</script>

</body>
</html>

EOF

#################################################
# GUI systemd
#################################################
sudo tee /etc/systemd/system/usbstreamer-gui.service >/dev/null <<EOF
[Unit]
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
# Enable
#################################################
sudo systemctl daemon-reload
sudo systemctl enable mediamtx super-streamer usbstreamer-gui
sudo systemctl restart mediamtx super-streamer usbstreamer-gui

echo "===================================================="
echo " INSTALL COMPLETE"
echo " RTSP : rtsp://<IP>:8554/usb"
echo " GUI  : http://<IP>:9000"
echo "===================================================="
