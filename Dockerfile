FROM ros:jazzy-ros-base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-jazzy-camera-calibration \
        ros-jazzy-usb-cam \
        ros-jazzy-image-publisher \
        ros-jazzy-image-view \
        ros-jazzy-image-transport-plugins \
        python3-opencv \
        v4l-utils \
        python3-colcon-common-extensions \
        python3-rosdep \
        git \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# Resolve build deps for the source workspace (ros2_ws/src) at image-build time
COPY ros2_ws/src /tmp/ws_src
RUN apt-get update \
 && (rosdep init || true) && rosdep update --rosdistro jazzy \
 && rosdep install --from-paths /tmp/ws_src --ignore-src -y --rosdistro jazzy \
      --skip-keys "ros_testing" \
 && rm -rf /tmp/ws_src /var/lib/apt/lists/*

# Source ROS in every shell so `docker compose run ... bash` just works
RUN echo 'source /opt/ros/jazzy/setup.bash' >> /root/.bashrc \
 && echo '[ -f /work/ros2_ws/install/setup.bash ] && source /work/ros2_ws/install/setup.bash' >> /root/.bashrc

WORKDIR /work
CMD ["bash"]
