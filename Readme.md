---

# **PiStream-Lite**

A One-Command RTSP Streaming Stack for Raspberry Pi 3B+, Pi 4, and Pi 5
USB Webcam → H.264 RTSP Stream with Auto-Recovery and Rollback Support

---

## Overview

PiStream-Lite is a minimal, reliable, and hardware-validated RTSP streaming setup for Raspberry Pi devices. It is specifically engineered for USB webcams and provides automatic recovery when the webcam is unplugged, reconnected, or when FFmpeg crashes. The setup also includes a complete rollback script to fully uninstall all components.

This project exists to solve a frustrating problem shared by many Raspberry Pi users:
getting a stable, low-latency H.264 RTSP stream from a USB webcam on Raspberry Pi boards without MotionEye, without MJPEG, and without unreliable community scripts.

### PiStream-Lite has been validated on:

* Raspberry Pi 3B+ (64-bit Only)
* Raspberry Pi 4
* Raspberry Pi 5

### Tested On:

* Raspberry Pi OS Bookworm 64-bit (recommended)

### Successfully tested hardware:

* Logitech C615 USB HD Webcam
* Additional generic UVC webcams

Designed and tested under real conditions:
cold plug, hot plug, delayed connection, boot with no camera, reconnect after minutes, RTSP viewer reconnects, docker conflict tests, v4l2 resets, ALSA failures, and systemd auto-restarts.

---

# Why This Project Exists

Over several days, I encountered nearly every failure scenario that Raspberry Pi users face when trying to stream a webcam over RTSP:

* OpenCV wheels missing for ARMv7 / ARM64 distributions
* MediaMTX flag changes (`--config` deprecated)
* MJPEG-only tools (MotionEye, mjpg-streamer) not supporting H.264
* FFmpeg ALSA device crashes
* Missing pixel format detection
* Camera showing YUYV422 but encoding pipeline incompatible
* MediaMTX failing to open port 8554
* Systemd repeatedly restarting due to wrapper script failures
* Hot-plug instability on older boards (Pi 3B+)
* Docker image portability issues across Pi generations

Many tutorials were incomplete, outdated, or contained configurations that no longer work with MediaMTX v1.15+.

Instead of following broken guides and incomplete examples, I built PiStream-Lite as a single click solution.

The goals:

1. Works on all recent Raspberry Pi boards
2. No need to manually install OpenCV
3. Pure FFmpeg → MediaMTX (H.264 RTSP)
4. Auto-recovers when the camera is unplugged
5. Auto-restarts FFmpeg and MediaMTX when failures occur
6. One command install, one command rollback
7. Under 2 minutes setup time
8. Zero manual configuration needed

After building and testing multiple generations of scripts, starting with OpenCV attempts, moving to FFmpeg-only pipelines, then a unified systemd wrapper with supervised auto-healing, PiStream-Lite emerged as the final, stable approach.

---

# Features

* True RTSP (H.264) streaming
* Auto-recovery when USB camera disconnects / reconnects
* Systemd-managed unified service
* Clean uninstall (rollback) script included
* Compatible with Pi 3B+, Pi 4, Pi 5
* Plug-and-play streaming
* No OpenCV dependency
* MediaMTX 1.15+ support
* Professional-grade stability
* Supports USB webcams up to 1080p
* Stream URL stays consistent:
  `rtsp://<pi-ip>:8554/usb`

---

# Folder Structure

```
PiStream-Lite/
│
├── setup.sh
├── rollback.sh
├── LICENSE
└── README.md
```

---

# Core Components

| Component                | Purpose                                       |
| ------------------------ | --------------------------------------------- |
| FFmpeg                   | Captures USB webcam → encodes to H.264        |
| MediaMTX                 | RTSP server that publishes the encoded stream |
| systemd unified service  | Supervises FFmpeg and MediaMTX                |
| Wrapper auto-heal script | Ensures continuous recovery                   |

---

# RTSP URL

After installation:

```
rtsp://<PI-IP>:8554/usb
```

---

# Supported Raspberry Pi Models

## Raspberry Pi Model Comparison Table

| Feature                | Pi 3B+         | Pi 4              | Pi 5         |
| ---------------------- | -------------- | ----------------- | ------------ |
| CPU                    | 1.4 GHz A53    | 1.5 GHz A72       | 2.0+ GHz A76 |
| USB Ports              | USB 2.0        | USB 2.0 + USB 3.0 | USB 3.0      |
| Encoding Stability     | Moderate       | Excellent         | Excellent    |
| Boot Speed             | Slow           | Fast              | Very Fast    |
| Hot-plug Recovery      | Reliable       | Very Reliable     | Excellent    |
| MediaMTX Performance   | Good           | Excellent         | Excellent    |
| Recommended Resolution | 640×480 / 720p | 720p / 1080p      | Full 1080p   |
| CPU Usage              | High           | Medium            | Low          |

PiStream-Lite dynamically adapts to all three models.

---

# Operating System Requirements

PiStream-Lite requires a **64-bit operating system**.
32-bit (armhf / ARMv7) systems are **not supported** due to MediaMTX and FFmpeg limitations.

### Verified Operating Systems

| Raspberry Pi Model | OS                           | Codename | Architecture    | Status        |
| ------------------ | ---------------------------- | -------- | --------------- | ------------- |
| Pi 3B+             | Debian GNU/Linux 12 Bookworm | bookworm | arm64 / aarch64 | Fully Working |
| Pi 4               | Raspberry Pi OS 64-bit       | bookworm | arm64 / aarch64 | Fully Working |
| Pi 5               | Raspberry Pi OS 64-bit       | bookworm | arm64 / aarch64 | Fully Working |

### Not Compatible

* Raspberry Pi OS 32-bit (armhf)
* Ubuntu ARMv7 32-bit variants
* Any 32-bit userland

---

# Installation

## 1. Copy the script to your Pi

```
scp setup.sh pi@<pi-ip>:/home/pi/
```

or download directly from GitHub after publishing.

## 2. Run the installer

```
chmod +x setup.sh
sudo ./setup.sh
```

Within one minute your RTSP stream is live.

---

# Uninstall / Rollback

```
chmod +x rollback.sh
sudo ./rollback.sh
```

This removes:

* systemd services
* MediaMTX
* config files
* wrapper scripts
* logs

Clean revert in moments.

---

# Performance Notes

## Video Pipeline

* Captures frames via V4L2
* Converts YUYV422 → YUV420P (H.264 friendly)
* Encodes via libx264 ultrafast preset
* Publishes to MediaMTX over localhost RTSP push

## Why Not Hardware Encoding?

On Pi 3B+/4/5, FFmpeg’s V4L2-M2M hardware H.264 encoder is unstable across USB webcams.
libx264 software encoding is more reliable and produces consistent results.

## Latency

* Typically between 150ms – 500ms
* Pi 5 has the lowest latency
* Recommended viewers: VLC, FFplay, Frigate, Agent DVR, OpenCV readers

---

# Alternatives and Why PiStream-Lite Is Different

| Tool                   | Issues                                          | Why PiStream-Lite Is Better                         |
| ---------------------- | ----------------------------------------------- | --------------------------------------------------- |
| MotionEye              | Uses MJPEG, not H.264 RTSP                      | PiStream-Lite provides true RTSP (H.264)            |
| mjpg-streamer          | Only MJPEG; poor performance                    | Not suitable for NVR / AI pipelines                 |
| GStreamer scripts      | Heavy configuration, unstable hot-plug          | PiStream-Lite self-recovers                         |
| OpenCV RTSP Pusher     | No ARM64 wheels, crashes on Pi3/Pi4             | PiStream-Lite avoids OpenCV entirely                |
| Docker MediaMTX        | Volume/privilege conflicts; webcam not detected | PiStream-Lite runs natively, full access to devices |
| Community bash scripts | Outdated MediaMTX flags                         | PiStream-Lite uses the latest syntax and configs    |

PiStream-Lite is currently one of the only fully-automated, Pi-wide compatible, hot-plug recovering, H.264-RTSP turnkey solutions.

---

# Project Journey (Condensed and Polished Technical Narrative)

This project started from a personal need: to deploy a reliable RTSP stream for embedded systems testing, telemetry dashboards, and AI pipelines without turning to MJPEG or incomplete scripts.

Initial attempts used OpenCV, but ARM64 wheels were unavailable across multiple Pi OS versions. Later scripts attempted to manually install wheels from piwheels, GitHub, and Ultralytics builds but each attempt resulted in ABI mismatches.

I then moved to FFmpeg-only implementations. This solved encoding problems, but MediaMTX configurations failed due to the `--config` flag being removed. I rewrote all MediaMTX YAML structures to the latest format.

Next, I implemented a two-service systemd design (MediaMTX + FFmpeg), but cold-plug/hot-plug testing caused broken synchronization. The fix was to develop a unified wrapper service controlling both processes. It sequentially:

* detects webcam
* starts MediaMTX
* waits for RTSP port
* launches FFmpeg
* restarts on crash

Finally, after testing on Pi3B+, Pi4, and Pi5 with multiple webcams (including the Logitech C615), the system proved stable, auto-recovering, and zero-touch.

The result is PiStream-Lite: a single-command setup that avoids the entire rabbit-hole of broken tutorials.

---

# Roadmap

* Optional audio support
* Optional 1080p H.264 tuning
* Dockerized deployment
* Web dashboard for monitoring stream health
* Multi-camera support
* Wi-Fi auto-reconfig script for headless setups
* OpenCV RTSP reader examples for ML pipelines

---

# License

MIT License
You may use, modify, and distribute freely.

---