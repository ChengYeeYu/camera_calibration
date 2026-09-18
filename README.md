# Camera calibration with ROS 2 (Docker)

Runs `camera_calibration` from ROS 2 Jazzy inside Docker. GUI shows on the Windows
desktop through WSLg. Image is already built (`camcal:jazzy`).

## 1. Print a checkerboard
```bash
docker compose run --rm ros python3 scripts/make_checkerboard.py 8 6 25   # -> calib/checkerboard_8x6_25mm.png
```
Print at 100% scale, glue to something flat, **measure a square with a ruler** — use that
value (in metres) for `--square`. `8x6` = inner corners, not squares.

## 2a. Calibrate from photos (works on WSL, no camera needed)
Take 20–30 photos with the camera you want to calibrate (same resolution/zoom/focus).
Cover the whole frame: corners, edges, near, far, tilted ±30–45°. Drop them in `images/`.
```bash
docker compose run --rm ros scripts/calib_from_images.sh 8x6 0.025
```
The photos are looped onto `/image_raw`; the calibrator GUI picks samples automatically
as the X / Y / Size / Skew bars fill. When **CALIBRATE** goes green, click it, then **SAVE**,
then press **q** in the window (COMMIT does nothing here — there is no camera driver to send it to).

## 2b. Calibrate live (needs a camera inside WSL)
Attach the webcam from PowerShell (admin): `usbipd list`, `usbipd bind --busid X-Y`,
`usbipd attach --wsl --busid X-Y`. Then check `ls /dev/video*` in WSL. If it's empty the
WSL kernel lacks UVC support and you'll need a custom kernel — use 2a instead.
```bash
docker compose run --rm ros scripts/calib_live.sh 8x6 0.025 /dev/video0
```

## 3. Get the result
Click **SAVE** in the GUI, then press **q** (or Esc) in the window — closing it with the
X button doesn't stop the node. The script then copies the output to
`calib/calibrationdata.tar.gz` and extracts `calib/ost.yaml` — the ROS `camera_info`
file (K, D, R, P) plus the sampled images. Reprojection error < 0.5 px is good.

Reuse it with the driver later (the file's `camera_name` is `narrow_stereo`; set the same
name or you get a harmless mismatch warning):
```bash
ros2 run usb_cam usb_cam_node_exe --ros-args -p video_device:=/dev/video0 \
  -p camera_name:=narrow_stereo -p camera_info_url:=file:///work/calib/ost.yaml
```

## Source workspace (`ros2_ws/`)
`ros2_ws/src/image_pipeline` is the `jazzy` branch of ros-perception/image_pipeline.
Build deps are baked into the image. Build inside the container:
```bash
docker compose run --rm ros
cd ros2_ws && colcon build --packages-up-to camera_calibration --symlink-install
```
`install/setup.bash` is auto-sourced in new shells and by the `scripts/*.sh` helpers, so the
source build overlays the apt package (`ros2 pkg prefix camera_calibration` →
`/work/ros2_ws/install/...`). Delete `ros2_ws/install/` to go back to the apt package.
Note: `build/ install/ log/` live on the Windows-mounted drive — first build is slower; fine after.

## Interactive shell
```bash
docker compose run --rm ros        # ROS already sourced
```
