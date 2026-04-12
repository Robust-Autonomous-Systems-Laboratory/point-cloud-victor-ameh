#!/usr/bin/env bash
# =============================================================================
# Step 1: Run MOLA SLAM on a ROS 2 bag file to produce a .mm metric map.
#
# Usage:
#   bash scripts/1_run_slam.sh <path/to/bag.mcap>
#
# Output:
#   <bag>.simplemap   -- raw SLAM trajectory + scans
#   <bag>.mm          -- metric map with static/dynamic point classification
#   trajectory.tum    -- robot trajectory in TUM format
# =============================================================================

set -e

if [ -z "$1" ]; then
    echo "Usage: bash scripts/1_run_slam.sh <path/to/bag.mcap>"
    exit 1
fi

BAG="$1"

if [ ! -f "$BAG" ]; then
    echo "Error: bag file not found: $BAG"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source /opt/ros/jazzy/setup.bash

echo "=== Step 1a: LiDAR odometry and simple map ==="
MOLA_SIMPLEMAP_GENERATE_LAZY_LOAD=true \
MOLA_ABS_MIN_SENSOR_RANGE=3.0 \
mola-lidar-odometry-cli \
  -c "$(ros2 pkg prefix mola_lidar_odometry)/share/mola_lidar_odometry/pipelines/lidar3d-default.yaml" \
  --input-rosbag2 "$BAG" \
  --lidar-sensor-label /rslidar_points \
  --imu-sensor-label /novatel/oem7/imu/data_raw \
  --output-tum-path trajectory.tum \
  --output-simplemap "${BAG}.simplemap"

echo ""
echo "=== Step 1b: Convert simple map to metric map (static/dynamic separation) ==="
sm2mm \
  -i "${BAG}.simplemap" \
  -o "${BAG}.mm" \
  -p "${SCRIPT_DIR}/sm2mm_voxels_static_dynamic_points.yaml"

echo ""
echo "=== Map info (use these bounds to set your crop region) ==="
mm-info "${BAG}.mm"

echo ""
echo "================================================================"
echo "Done! Map saved to: ${BAG}.mm"
echo ""
echo "Next steps:"
echo "  1. Inspect your map visually (see Step 2 in the README):"
echo "       source /opt/ros/jazzy/setup.bash"
echo "       mm-viewer -l libmola_metric_maps.so -t trajectory.tum ${BAG}.mm"
echo "  2. Once you are happy with the map, edit scripts/crop_filter.yaml"
echo "     to set the region you want to keep, then run:"
echo "       bash scripts/2_process_map.sh ${BAG}.mm"
echo "================================================================"
