#!/usr/bin/env bash
# Live webcam calibration (needs the camera attached via usbipd, e.g. /dev/video0).
# Usage: calib_live.sh [COLSxROWS] [square_m] [/dev/videoN] [WIDTHxHEIGHT]
#   e.g. calib_live.sh 8x6 0.025 /dev/video0 960x600   (camera supports 1920x1200 or 960x600)
# In the GUI: move the board until CALIBRATE goes green, click it, click SAVE (and optionally COMMIT),
# then press q (or Esc) in the window.
set -e
source /opt/ros/jazzy/setup.bash
[ -f /work/ros2_ws/install/setup.bash ] && source /work/ros2_ws/install/setup.bash   # prefer the source build if built
SIZE=${1:-8x6}
SQUARE=${2:-0.025}
DEV=${3:-/dev/video0}
RES=${4:-960x600}
WIDTH=${RES%x*}
HEIGHT=${RES#*x}
OUT=/tmp/calibrationdata.tar.gz    # hard-coded in cameracalibrator's SAVE button

[ -e "$DEV" ] || { echo "$DEV not found. Attach the camera with usbipd on Windows first." >&2; exit 1; }
rm -f "$OUT"   # don't report a stale result from an earlier run in this container

ros2 run usb_cam usb_cam_node_exe --ros-args -p video_device:="$DEV" -p pixel_format:=yuyv2rgb \
  -p image_width:="$WIDTH" -p image_height:="$HEIGHT" -p framerate:=30.0 -p brightness:=0 &
CAM=$!
trap "kill $CAM 2>/dev/null; pkill -f usb_cam_node_exe 2>/dev/null; true" EXIT   # ros2 run does not forward SIGTERM to the node
sleep 2
kill -0 "$CAM" 2>/dev/null || { echo "usb_cam failed to start (see errors above); try a different pixel_format/resolution from 'v4l2-ctl -d $DEV --list-formats-ext'." >&2; exit 1; }

# usb_cam's node name is usb_cam, so its camera_info_manager service is /usb_cam/set_camera_info
ros2 run camera_calibration cameracalibrator \
  --size "$SIZE" --square "$SQUARE" \
  --ros-args -r image:=/image_raw -r camera/set_camera_info:=/usb_cam/set_camera_info || true

if [ -f "$OUT" ]; then
  cp "$OUT" "/work/calib/calibrationdata_${RES}.tar.gz"
  tar -xzf "$OUT" -O ost.yaml > "/work/calib/cam_${RES}.yaml"
  echo "Saved: calib/calibrationdata_${RES}.tar.gz and calib/cam_${RES}.yaml"
else
  echo "No calibration saved (did you click SAVE?)"
fi
