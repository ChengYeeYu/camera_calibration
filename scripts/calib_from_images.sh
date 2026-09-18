#!/usr/bin/env bash
# Publish the photos in /work/images on a loop and run the ROS calibrator GUI on them.
# Usage: calib_from_images.sh [COLSxROWS] [square_m]
# In the GUI: wait for CALIBRATE to go green, click it, click SAVE, then press q (or Esc) in the window.
set -e
source /opt/ros/jazzy/setup.bash
[ -f /work/ros2_ws/install/setup.bash ] && source /work/ros2_ws/install/setup.bash   # prefer the source build if built
SIZE=${1:-8x6}
SQUARE=${2:-0.025}
OUT=/tmp/calibrationdata.tar.gz    # hard-coded in cameracalibrator's SAVE button

shopt -s nullglob
IMGS=(/work/images/*.jpg /work/images/*.jpeg /work/images/*.png /work/images/*.JPG /work/images/*.JPEG /work/images/*.PNG)
if [ ${#IMGS[@]} -eq 0 ]; then
  echo "No images in /work/images — drop your checkerboard photos there first." >&2
  exit 1
fi
echo "Found ${#IMGS[@]} images. Pattern ${SIZE}, square ${SQUARE} m."
rm -f "$OUT"   # don't report a stale result from an earlier run in this container

# image_publisher only takes one file, so cycle through them with a small python node.
python3 - "${IMGS[@]}" <<'PY' &
import sys, time, cv2, rclpy
from rclpy.node import Node
from sensor_msgs.msg import Image
from cv_bridge import CvBridge
files = sys.argv[1:]
rclpy.init()
n = Node('image_cycler'); pub = n.create_publisher(Image, '/image_raw', 1); br = CvBridge()
i = 0
try:
    while rclpy.ok():
        img = cv2.imread(files[i % len(files)])
        if img is None:
            n.get_logger().warn(f"could not read {files[i % len(files)]}, skipping")
        else:
            m = br.cv2_to_imgmsg(img, 'bgr8'); m.header.frame_id = 'camera'
            m.header.stamp = n.get_clock().now().to_msg(); pub.publish(m)
        i += 1; time.sleep(0.7)
except KeyboardInterrupt:
    pass
PY
PUB=$!
trap "kill $PUB 2>/dev/null" EXIT

# No camera driver here, so there is no set_camera_info service: skip the check (COMMIT won't work, SAVE will).
ros2 run camera_calibration cameracalibrator \
  --size "$SIZE" --square "$SQUARE" --no-service-check \
  --ros-args -r image:=/image_raw || true

if [ -f "$OUT" ]; then
  cp "$OUT" /work/calib/
  tar -xzf "$OUT" -C /work/calib ost.yaml
  echo "Saved: calib/calibrationdata.tar.gz and calib/ost.yaml"
else
  echo "No calibration saved (did you click SAVE?)"
fi
