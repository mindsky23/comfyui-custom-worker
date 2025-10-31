#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

# Copy custom_nodes from Network Volume if available
# Check common volume mount paths used in RunPod
VOLUME_NODES_COPIED=false
if [ -d "/workspace/ComfyUI/custom_nodes" ] && [ "$(ls -A /workspace/ComfyUI/custom_nodes 2>/dev/null)" ]; then
    echo "worker-comfyui: Copying custom_nodes from /workspace/ComfyUI/custom_nodes"
    mkdir -p /comfyui/custom_nodes
    cp -rn /workspace/ComfyUI/custom_nodes/* /comfyui/custom_nodes/ 2>/dev/null || true
    VOLUME_NODES_COPIED=true
elif [ -d "/runpod-volume/ComfyUI/custom_nodes" ] && [ "$(ls -A /runpod-volume/ComfyUI/custom_nodes 2>/dev/null)" ]; then
    echo "worker-comfyui: Copying custom_nodes from /runpod-volume/ComfyUI/custom_nodes"
    mkdir -p /comfyui/custom_nodes
    cp -rn /runpod-volume/ComfyUI/custom_nodes/* /comfyui/custom_nodes/ 2>/dev/null || true
    VOLUME_NODES_COPIED=true
elif [ -d "/workspace/custom_nodes" ] && [ "$(ls -A /workspace/custom_nodes 2>/dev/null)" ]; then
    echo "worker-comfyui: Copying custom_nodes from /workspace/custom_nodes"
    mkdir -p /comfyui/custom_nodes
    cp -rn /workspace/custom_nodes/* /comfyui/custom_nodes/ 2>/dev/null || true
    VOLUME_NODES_COPIED=true
else
    echo "worker-comfyui: No custom_nodes found in Network Volume, using nodes from image"
fi

# Install dependencies for custom_nodes if they were copied from volume
if [ "$VOLUME_NODES_COPIED" = true ]; then
    echo "worker-comfyui: Installing dependencies for custom_nodes from volume"
    cd /comfyui && \
    find custom_nodes -maxdepth 2 -name "requirements.txt" -type f 2>/dev/null | while read req; do
        echo "Installing dependencies from $req"
        uv pip install -r "$req" || true
    done
    cd /
fi

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py
fi