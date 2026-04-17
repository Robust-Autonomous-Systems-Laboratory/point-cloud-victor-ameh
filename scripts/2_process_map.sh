#!/usr/bin/env bash
set -eo pipefail

# ==============================================================================
# Step 2: Crop, export, decimate, and convert a .mm map to Potree format.
#
# Usage:
#   bash scripts/2_process_map.sh <path/to/map.mm> [voxel_size_m]
#
# Arguments:
#   map.mm        -- metric map produced by 1_run_slam.sh
#   voxel_size_m  -- voxel decimation size in meters (default: 0.04)
#
# Output:
#   pointclouds/<map_name>/  -- Potree tiles ready for GitHub Pages
# ==============================================================================

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: bash scripts/2_process_map.sh <path/to/map.mm> [voxel_size_m]"
    exit 1
fi

MM="$1"
VOXEL="${2:-0.04}"

if [[ ! -f "$MM" ]]; then
    echo "Error: map file not found: $MM"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NAME="$(basename "$MM" .mm)"

CROPPED_MM="${NAME}_cropped.mm"
PLY_PREFIX="${NAME}"

# Use the cleaner static layer for web export:
PLY_FILE="${NAME}_static_map_cropped.ply"

LAZ_FILE="${NAME}.laz"
POTREE_DIR="${REPO_DIR}/pointclouds/${NAME}"

source /opt/ros/jazzy/setup.bash

# Always run from the repo root so PotreeConverter can find liblaszip.so
cd "$REPO_DIR"

echo "=== Step 2a: Crop map to bounding box ==="
echo "  Using filter: ${SCRIPT_DIR}/crop_filter.yaml"

mm-filter \
    -i "$MM" \
    -p "${SCRIPT_DIR}/crop_filter.yaml" \
    -o "$CROPPED_MM"

echo
echo "=== Inspecting cropped map — close the viewer window to continue ==="
mm-info "$CROPPED_MM"

# Keep viewer for inspection, but don't let a viewer crash stop the pipeline.
mm-viewer -l libmola_metric_maps.so "$CROPPED_MM" || true

echo
echo "=== Step 2b: Export cropped map to PLY ==="
echo "  Export prefix: ${PLY_PREFIX}"
echo "  Expected web-export layer: ${PLY_FILE}"

# mm2ply may warn/error about the empty 'raw' layer; that can be ignored.
# The PLY files are typically written before that warning/error is emitted.
mm2ply \
    -i "$CROPPED_MM" \
    -o "$PLY_PREFIX" \
    --export-fields x,y,z,intensity \
    -b || true

if [[ ! -f "$PLY_FILE" ]]; then
    echo "Error: expected PLY file not found: $PLY_FILE"
    echo "Available PLY files in repo root:"
    ls -1 "${NAME}"*.ply 2>/dev/null || echo "  (none found)"
    echo
    echo "Check that 'static_map_cropped' exists in ${CROPPED_MM}:"
    echo "  mm-info ${CROPPED_MM}"
    exit 1
fi

echo
echo "=== Step 2c: Decimate and convert to LAZ (voxel size: ${VOXEL} m) ==="
python3 "${SCRIPT_DIR}/ply_to_laz.py" \
    "$PLY_FILE" \
    "$LAZ_FILE" \
    --voxel-size "$VOXEL"

if [[ ! -f "$LAZ_FILE" ]]; then
    echo "Error: LAZ file was not created: $LAZ_FILE"
    exit 1
fi

echo
echo "=== Step 2d: Convert LAZ to Potree tiles ==="
mkdir -p "${REPO_DIR}/pointclouds"
rm -rf "$POTREE_DIR"

LD_LIBRARY_PATH="${REPO_DIR}:${LD_LIBRARY_PATH:-}" \
    "${REPO_DIR}/PotreeConverter" \
    "$LAZ_FILE" \
    -o "$POTREE_DIR"

if [[ ! -f "${POTREE_DIR}/metadata.json" ]]; then
    echo "Error: Potree metadata not found: ${POTREE_DIR}/metadata.json"
    exit 1
fi

echo
echo "=============================================================="
echo "Done! Potree tiles written to: pointclouds/${NAME}/"
echo "=============================================================="
echo
echo "Generated files:"
echo "  Cropped map : ${CROPPED_MM}"
echo "  PLY         : ${PLY_FILE}"
echo "  LAZ         : ${LAZ_FILE}"
echo "  Potree dir  : pointclouds/${NAME}/"
echo
echo "Next steps:"
echo "  1. Edit index.html and replace YOUR_MAP_NAME with: ${NAME}"
echo "  2. Example:"
echo "       Potree.loadPointCloud(\"./pointclouds/${NAME}/metadata.json\", \"map\", e => {"
echo "  3. Commit and push:"
echo "       git add -f pointclouds/${NAME} index.html"
echo "       git commit -m \"Add point cloud map: ${NAME}\""
echo "       git push"
echo
