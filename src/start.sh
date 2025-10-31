#!/usr/bin/env bash

set -euo pipefail

log() { printf "%s | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Use libtcmalloc for better memory management (best-effort)
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1 || true)"
if [ -n "${TCMALLOC:-}" ]; then
  export LD_PRELOAD="${TCMALLOC}"
  log "worker-comfyui: Using ${TCMALLOC} via LD_PRELOAD"
else
  log "worker-comfyui: libtcmalloc not found (continuing without it)"
fi

# Ensure ComfyUI-Manager runs in offline network mode inside the container
log "worker-comfyui: Setting ComfyUI-Manager network mode to offline"
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

# Copy custom_nodes from Network Volume if available
log "worker-comfyui: Checking for custom_nodes on mounted volumes"
VOLUME_NODES_COPIED=false
if [ -d "/workspace/ComfyUI/custom_nodes" ] && [ "$(ls -A /workspace/ComfyUI/custom_nodes 2>/dev/null)" ]; then
    log "worker-comfyui: Copying from /workspace/ComfyUI/custom_nodes"
    mkdir -p /comfyui/custom_nodes
    cp -rn /workspace/ComfyUI/custom_nodes/* /comfyui/custom_nodes/ 2>/dev/null || true
    VOLUME_NODES_COPIED=true
elif [ -d "/runpod-volume/ComfyUI/custom_nodes" ] && [ "$(ls -A /runpod-volume/ComfyUI/custom_nodes 2>/dev/null)" ]; then
    log "worker-comfyui: Copying from /runpod-volume/ComfyUI/custom_nodes"
    mkdir -p /comfyui/custom_nodes
    cp -rn /runpod-volume/ComfyUI/custom_nodes/* /comfyui/custom_nodes/ 2>/dev/null || true
    VOLUME_NODES_COPIED=true
elif [ -d "/workplace/ComfyUI/custom_nodes" ] && [ "$(ls -A /workplace/ComfyUI/custom_nodes 2>/dev/null)" ]; then
    log "worker-comfyui: Copying from /workplace/ComfyUI/custom_nodes"
    mkdir -p /comfyui/custom_nodes
    cp -rn /workplace/ComfyUI/custom_nodes/* /comfyui/custom_nodes/ 2>/dev/null || true
    VOLUME_NODES_COPIED=true
elif [ -d "/workspace/custom_nodes" ] && [ "$(ls -A /workspace/custom_nodes 2>/dev/null)" ]; then
    log "worker-comfyui: Copying from /workspace/custom_nodes"
    mkdir -p /comfyui/custom_nodes
    cp -rn /workspace/custom_nodes/* /comfyui/custom_nodes/ 2>/dev/null || true
    VOLUME_NODES_COPIED=true
else
    log "worker-comfyui: No custom_nodes found in Network Volume, using nodes from image"
fi

# Install dependencies for custom_nodes if they were copied from volume
if [ "$VOLUME_NODES_COPIED" = true ]; then
    log "worker-comfyui: Installing dependencies for copied custom_nodes"
    cd /comfyui && \
    find custom_nodes -maxdepth 2 -name "requirements.txt" -type f 2>/dev/null | while read req; do
        log "worker-comfyui: pip install -r ${req}"
        uv pip install -r "$req" || true
    done
    cd /
fi

# Inventory custom nodes to aid debugging
if [ -d "/comfyui/custom_nodes" ]; then
  log "worker-comfyui: Listing custom_nodes (depth=1)"
  find /comfyui/custom_nodes -maxdepth 1 -mindepth 1 -type d -printf "%f\n" | sort | sed 's/^/  - /'
fi

log "worker-comfyui: Starting ComfyUI"
export PYTHONUNBUFFERED=1

# Performance optimizations for RTX 4090 and high-end GPUs
# Enable PyTorch optimizations for faster inference
export PYTORCH_ENABLE_MPS_FALLBACK=0  # Disable MPS (we're using CUDA)
export TORCH_CUDNN_BENCHMARK=1        # Enable cuDNN autotuning
export TORCH_CUDNN_DETERMINISTIC=0    # Allow non-deterministic algorithms (faster)

# Apply runtime PyTorch optimizations (TF32, cuDNN benchmark, memory settings)
if [ -f "/optimize_pytorch.py" ]; then
    log "worker-comfyui: Applying PyTorch performance optimizations for RTX 4090"
    python /optimize_pytorch.py || log "worker-comfyui: Warning - PyTorch optimization script failed"
fi

# Note: LowVRAM mode is often enabled automatically by models
# If you have 24GB+ VRAM (RTX 4090), consider disabling lowVRAM in workflow settings

# Serve the API and don't shutdown the container
wait_for_server() {
  local host="127.0.0.1" port="8188" timeout="180" elapsed=0
  while ! (exec 3<>/dev/tcp/${host}/${port}) 2>/dev/null; do
    sleep 1; elapsed=$((elapsed+1))
    if [ "$elapsed" -eq 1 ] || [ $((elapsed % 10)) -eq 0 ]; then
      log "worker-comfyui: Waiting for ComfyUI on ${host}:${port} (${elapsed}s)"
    fi
    if [ "$elapsed" -ge "$timeout" ]; then
      log "worker-comfyui: ComfyUI did not become ready within ${timeout}s"
      if [ -f "/comfyui/user/comfyui.log" ]; then
        log "worker-comfyui: Last 200 lines of /comfyui/user/comfyui.log"
        tail -n 200 /comfyui/user/comfyui.log || true
      fi
      return 1
    fi
  done
  log "worker-comfyui: ComfyUI is accepting connections on ${host}:${port}"
  return 0
}

: "${COMFY_LOG_LEVEL:=DEBUG}"

if [ "${SERVE_API_LOCALLY:-false}" = "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout &
    COMFY_PID=$!
    log "worker-comfyui: ComfyUI PID=${COMFY_PID} (listen mode)"
    if wait_for_server; then
      log "worker-comfyui: Starting RunPod Handler (local serve)"
      python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
    else
      log "worker-comfyui: Handler not started due to ComfyUI readiness failure"
      exit 1
    fi
else
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout &
    COMFY_PID=$!
    log "worker-comfyui: ComfyUI PID=${COMFY_PID}"
    if wait_for_server; then
      log "worker-comfyui: Starting RunPod Handler"
      python -u /handler.py
    else
      log "worker-comfyui: Handler not started due to ComfyUI readiness failure"
      exit 1
    fi
fi