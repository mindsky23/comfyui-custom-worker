# Minimal Dockerfile based on working hearmeman/comfyui-wan-template:v10
# This approach uses ComfyUI from the mounted Volume (/workspace)
# instead of installing it inside the image
#
# Usage:
#   docker build -f Dockerfile.volume-based -t your-image-name .
#   docker run --gpus all -v "C:\comfyui:/workspace" -p 8188:8188 your-image-name
#
# This matches your working setup where ComfyUI is already in the Volume

# Use the proven working base image
FROM hearmeman/comfyui-wan-template:v10

# Set working directory
WORKDIR /

# Install Python dependencies for RunPod handler
# Using the same Python environment that ComfyUI uses
RUN pip install --no-cache-dir runpod requests websocket-client || \
    (echo "Warning: pip install failed, trying with pip3" && \
     pip3 install --no-cache-dir runpod requests websocket-client || true)

# Copy handler and startup script
COPY handler.py /handler.py
COPY src/start-volume-based.sh /start.sh
RUN chmod +x /start.sh

# Environment variables (matching your working setup)
ENV PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:256
ENV MALLOC_ARENA_MAX=2
ENV PYTHONUNBUFFERED=1

# Optional: Support same environment variables as your working command
ENV download_480p_native_models=true
ENV download_720p_native_models=true
ENV download_wan_fun_and_sdxl_helper=true
ENV download_vace=true

# Set the command - matches your working command structure:
# 1. Install sageattention
# 2. Start ComfyUI from Volume using start_script.sh
# 3. Start RunPod handler
CMD ["bash", "-c", "pip install --no-cache-dir sageattention || pip3 install --no-cache-dir sageattention || true && /start.sh"]

