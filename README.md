# Camera calibration with ROS 2 (Docker)

Runs `camera_calibration` from ROS 2 Jazzy inside Docker. GUI shows on the Windows
desktop through WSLg. Image is `camcal:jazzy`.

**Camera:** Arducam B0495 (USB3, 2.3 MP). Outputs **YUYV only** (no MJPG/H.264):

| Resolution | fps            |
|------------|----------------|
| 1920x1200  | 15 / 30 / 50   |
| 960x600    | 15 / 30 / 60 / 80 |

Other sizes (e.g. 640x480, 1280x720) are not camera modes and make `usb_cam` abort — see
[640x480](#640x480). Calibrate at the resolution you'll use; the result only applies to that resolution.

## Contents
1. [Attach the camera to WSL](#1-attach-the-camera-to-wsl)
2. [Container](#2-container)
3. [Print a checkerboard](#3-print-a-checkerboard)
4. [Calibrate](#4-calibrate) — helper script, manual, or from photos
5. [Check the quality](#5-check-the-quality)
6. [Use the calibration](#6-use-the-calibration)
7. [Troubleshooting](#7-troubleshooting)
8. [Source workspace](#8-source-workspace-ros2_ws)

## 1. Attach the camera to WSL

Windows PowerShell (admin):
```powershell
winget install usbipd
usbipd list                          # find BUSID, e.g. 2-3
usbipd bind --busid 2-3              # once per device

# every plug-in / reboot (use a USB3 port + cable, else low fps / fails at 1920x1200)
usbipd attach --wsl --busid 2-3
usbipd detach --wsl --busid 2-3      # give it back to Windows when done
```

WSL:
```bash
sudo modprobe uvcvideo
ls /dev/video*                       # usually /dev/video0 (+ video1 = metadata, not usable)
```
If `/dev/video*` is empty after attaching, the WSL kernel lacks UVC support — use
[calibrate from photos](#4c-from-photos-no-camera-needed) instead.

## 2. Container

The image build needs the `image_pipeline` submodule, so after a fresh clone run
`git submodule update --init` first.
```bash
cd ~/Projects/camera_calibration
docker compose build                 # only after editing the Dockerfile
docker compose up -d                 # start container "camcal"
docker compose exec ros bash         # open a shell (repeat for more terminals); ROS already sourced
docker compose down                  # stop (also clears stuck drivers / stale nodes)
```
Ad-hoc alternative: `docker compose run --rm ros`, then `docker exec -it <name> bash` for a 2nd shell.

Host folders `calib/`, `images/`, `scripts/`, `ros2_ws/` are mounted under `/work/` in the container.

Inspect the camera from inside the container:
```bash
v4l2-ctl -d /dev/video0 --list-formats-ext    # supported formats / fps
v4l2-ctl -d /dev/video0 -l                    # controls (brightness, gain, exposure)
```

## 3. Print a checkerboard

```bash
docker compose run --rm ros python3 scripts/make_checkerboard.py 8 6 25   # -> calib/checkerboard_8x6_25mm.png
```
Print at 100% scale, glue to something flat, **measure a square with a ruler** — use that
value (in metres) for `--square`. `8x6` = inner corners, not squares. The examples below use
`0.024` (the measured size of the current print).

## 4. Calibrate

> **Only one camera driver at a time.** The helper script starts its own driver, so stop any
> manual `usb_cam` first. See [Troubleshooting](#7-troubleshooting).

In the calibrator GUI: move the board around (corners, edges, near, far, tilted ±30–45°) until
the X / Y / Size / Skew bars fill and **CALIBRATE** goes green → click **CALIBRATE** → **SAVE** →
press **q** (or Esc) in the window. Closing it with the X button doesn't stop the node.
SAVE always writes `/tmp/calibrationdata.tar.gz` (hard-coded); it contains `ost.yaml` — the ROS
`camera_info` file (K, D, R, P) — plus the sampled images. The tarballs are large (~85 MB at
1920x1200) and git-ignored; the `cam_*.yaml` files are what you keep.

### 4a. Helper script (live camera)

```bash
scripts/calib_live.sh 8x6 0.024 /dev/video0 960x600      # -> calib/cam_960x600.yaml
scripts/calib_live.sh 8x6 0.024 /dev/video0 1920x1200    # -> calib/cam_1920x1200.yaml
```
Arguments: `[COLSxROWS] [square_m] [/dev/videoN] [WIDTHxHEIGHT]` (defaults `8x6 0.025 /dev/video0 960x600`).
It starts the driver and calibrator, then saves `calib/calibrationdata_<RES>.tar.gz` and
`calib/cam_<RES>.yaml`, and stops the driver on exit.

### 4b. Manual (two terminals)

Terminal 1 — camera driver (pick **one** resolution):
```bash
ros2 run usb_cam usb_cam_node_exe --ros-args \
  -p video_device:=/dev/video0 -p pixel_format:=yuyv2rgb \
  -p image_width:=960 -p image_height:=600 -p framerate:=30.0 \
  -p brightness:=0
#   full res: -p image_width:=1920 -p image_height:=1200
```
`brightness:=0` matters: usb_cam's default of 50 nearly maxes this camera's −64..64 range and
overexposes the image.

Terminal 2 — check the stream:
```bash
ros2 topic hz /image_raw                                  # no output = no driver publishing
ros2 topic echo /image_raw --field width --once           # confirm the resolution actually applied
ros2 run image_view image_view --ros-args -r image:=/image_raw
```

Terminal 2 — calibrate:
```bash
ros2 run camera_calibration cameracalibrator \
  --size 8x6 --square 0.024 \
  --ros-args -r image:=/image_raw -r camera/set_camera_info:=/usb_cam/set_camera_info
```
Warnings about `left_camera`/`right_camera` not found, `/left` `/right` QoS, or `XDG_RUNTIME_DIR`
are harmless (stereo checks).

After SAVE + q, store the result per resolution:
```bash
RES=960x600        # or 1920x1200
cp /tmp/calibrationdata.tar.gz /work/calib/calibrationdata_$RES.tar.gz
tar -xzf /tmp/calibrationdata.tar.gz -O ost.yaml > /work/calib/cam_$RES.yaml
```

### 4c. From photos (no camera needed)

Take 20–30 photos with the camera you want to calibrate (same resolution/zoom/focus), covering
the whole frame as above. Drop them in `images/`, then:
```bash
docker compose run --rm ros scripts/calib_from_images.sh 8x6 0.024
```
The photos are looped onto `/image_raw` and the calibrator picks samples automatically.
COMMIT does nothing here (no camera driver to send it to) — use SAVE. Output:
`calib/calibrationdata.tar.gz` and `calib/ost.yaml`.

## 5. Check the quality

After CALIBRATE the GUI sidebar shows **`lin.`** — RMS straightness error (px) of the undistorted
board rows. < 0.5 good, 0.5–1 usable, > 1 bad. Straight edges in the rectified view must stay
straight into the corners. Also sanity-check the YAML: fx ≈ fy, principal point near the image centre.

## 6. Use the calibration

Calibrated files: `calib/cam_960x600.yaml`, `calib/cam_1920x1200.yaml` (`camera_name: default_cam`).
Width/height must match the YAML, and `camera_name` must match the name inside it (else a
harmless mismatch warning):
```bash
ros2 run usb_cam usb_cam_node_exe --ros-args -p video_device:=/dev/video0 -p pixel_format:=yuyv2rgb \
  -p image_width:=960 -p image_height:=600 -p brightness:=0 \
  -p camera_name:=default_cam -p camera_info_url:=file:///work/calib/cam_960x600.yaml
ros2 topic echo /camera_info --once   # K/D should be the calibrated values
```

### Compressed images
Done in software — the camera itself only sends raw YUYV. The `image_transport` plugins are
preinstalled, so `/image_raw/compressed` (JPEG) is published automatically:
```bash
ros2 topic list | grep compressed
ros2 topic hz /image_raw/compressed
ros2 param set /usb_cam image_raw.jpeg_quality 80   # lower = smaller
```
This saves network / rosbag bandwidth, **not** USB bandwidth.

### 640x480
Not a camera mode. `calib/cam_640x480.yaml` is derived from `cam_960x600.yaml` and is only valid
for images made by: center-crop 960x600 → 800x600 (x_offset 80), then resize ×0.8 → 640x480.
Prefer 960x600 + `cam_960x600.yaml` unless 640x480 is really required.

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| `/dev/video*` gone | `usbipd detach` + `attach` again (unplug/replug if needed) |
| Camera comes back as `/dev/video4`, `video6`, … | Use the **lower** number of the pair in every command, or restart the container to get `/dev/video0` back |
| `Device or resource busy`, `terminate called after throwing an instance of 'char*'`, or black calibrator window | A 2nd driver is running. `ros2 node list` must show `/usb_cam` only once; `pkill usb_cam_node` (`pkill -9` if stuck) or `docker compose down` |
| Calibrator window stays black | No images — check the driver terminal and `ros2 topic hz /image_raw` |
| `InvalidParameterTypeException` | A stray `^C` got into the command (e.g. `brightness:=0^C`) making it a string — retype cleanly |
| usb_cam aborts at start | Unsupported mode: use `yuyv2rgb` at 1920x1200 or 960x600 (`mjpeg2rgb` / 1280x720 fail) |
| Low fps / fails at 1920x1200 | Use a USB3 port and cable |
| Image overexposed | Set `-p brightness:=0` |

## 8. Source workspace (`ros2_ws/`)

`ros2_ws/src/image_pipeline` is the `jazzy` branch of ros-perception/image_pipeline (git submodule).
Build deps are baked into the image. Build inside the container:
```bash
cd /work/ros2_ws
colcon build --packages-up-to camera_calibration --symlink-install
ros2 pkg prefix camera_calibration   # -> /work/ros2_ws/install/...
```
`install/setup.bash` is auto-sourced in new shells and by the `scripts/*.sh` helpers, so the
source build overlays the apt package. Delete `ros2_ws/install/` to go back to the apt package.
Note: `build/ install/ log/` live on the Windows-mounted drive — first build is slower; fine after.
