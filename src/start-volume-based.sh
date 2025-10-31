#!/usr/bin/env bash

set -euo pipefail

log() { printf "%s | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Check if ComfyUI exists in /workspace
if [ ! -d "/workspace/ComfyUI" ]; then
    log "ERROR: ComfyUI not found in /workspace/ComfyUI"
    log "Please ensure ComfyUI is properly mounted in the Volume at /workspace"
    exit 1
fi

log "worker-comfyui: ComfyUI found in /workspace/ComfyUI"

# Setup models directory: create symlink from /workspace/ComfyUI/models to /workspace/models
# This allows ComfyUI to find models in /workspace/models (your current structure)
if [ -d "/workspace/models" ] && [ ! -L "/workspace/ComfyUI/models" ] && [ ! -d "/workspace/ComfyUI/models" ]; then
    log "worker-comfyui: Creating symlink /workspace/ComfyUI/models -> /workspace/models"
    ln -s /workspace/models /workspace/ComfyUI/models
elif [ -d "/workspace/ComfyUI/models" ]; then
    log "worker-comfyui: Models directory already exists at /workspace/ComfyUI/models"
elif [ ! -d "/workspace/models" ]; then
    log "worker-comfyui: WARNING: /workspace/models not found - ComfyUI may not find models"
fi

# Setup extra_model_paths.yaml to point to /workspace/models
if [ ! -f "/workspace/ComfyUI/extra_model_paths.yaml" ]; then
    log "worker-comfyui: Creating extra_model_paths.yaml to use /workspace/models"
    cat > /workspace/ComfyUI/extra_model_paths.yaml << 'EOF'
runpod_worker_comfy:
  base_path: /workspace
  checkpoints: models/checkpoints/
  clip: models/clip/
  clip_vision: models/clip_vision/
  configs: models/configs/
  controlnet: models/controlnet/
  embeddings: models/embeddings/
  loras: models/loras/
  upscale_models: models/upscale_models/
  vae: models/vae/
  unet: models/unet/
  text_encoders: models/text_encoders/
  diffusion_models: models/diffusion_models/
EOF
else
    log "worker-comfyui: extra_model_paths.yaml already exists, using existing configuration"
fi

log "worker-comfyui: Note: sageattention installation happens before this script runs (see CMD)"

# Function to cleanup ComfyUI process on exit
cleanup() {
    log "worker-comfyui: Shutting down ComfyUI (PID: ${COMFY_PID:-none})"
    if [ -n "${COMFY_PID:-}" ]; then
        kill -TERM "$COMFY_PID" 2>/dev/null || true
        wait "$COMFY_PID" 2>/dev/null || true
    fi
    # Also try to kill any remaining Python processes related to ComfyUI
    pkill -f "main.py.*8188" 2>/dev/null || true
    log "worker-comfyui: Cleanup complete"
}

# Set up signal handlers to cleanup on exit
trap cleanup EXIT INT TERM

# Check if start_script.sh exists in the base image (from hearmeman/comfyui-wan-template)
if [ -f "/start_script.sh" ]; then
    log "worker-comfyui: Using start_script.sh from base image"
    # Start ComfyUI in background using the existing script from the image
    # This script should work with /workspace mount (matching your setup)
    bash /start_script.sh &
    COMFY_PID=$!
elif [ -f "/workspace/ComfyUI/main.py" ]; then
    log "worker-comfyui: Starting ComfyUI directly from /workspace/ComfyUI"
    cd /workspace/ComfyUI
    python main.py --listen 0.0.0.0 --port 8188 &
    COMFY_PID=$!
else
    log "ERROR: Cannot find ComfyUI startup script or main.py"
    log "worker-comfyui: Looking for ComfyUI in /workspace/ComfyUI..."
    ls -la /workspace/ || echo "  /workspace not found"
    ls -la /workspace/ComfyUI/ 2>/dev/null || echo "  /workspace/ComfyUI not found"
    exit 1
fi

log "worker-comfyui: ComfyUI started with PID $COMFY_PID"

# Wait for ComfyUI API to be ready
log "worker-comfyui: Waiting for ComfyUI API to be ready..."
max_attempts=120
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if curl -s http://127.0.0.1:8188/ > /dev/null 2>&1; then
        log "worker-comfyui: ComfyUI API is reachable"
        break
    fi
    attempt=$((attempt + 1))
    if [ $((attempt % 10)) -eq 0 ]; then
        log "worker-comfyui: Still waiting... (attempt $attempt/$max_attempts)"
    fi
    sleep 1
done

if [ $attempt -ge $max_attempts ]; then
    log "ERROR: ComfyUI API did not become ready after $max_attempts attempts"
    log "worker-comfyui: Checking ComfyUI process..."
    ps aux | grep -E "(python|ComfyUI)" | head -5
    exit 1
fi

# Go back to root and start RunPod handler
cd /
log "worker-comfyui: Starting RunPod handler..."

# Start the handler (it will connect to ComfyUI at 127.0.0.1:8188)
# The handler uses runpod.serverless.start() which expects to run as main process
exec python3 /handler.py

