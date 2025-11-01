# Build argument for base image selection
# Using devel variant for CUDA toolkit (includes nvcc, CUDA headers, CUDA_HOME)
# CUDA 12.8.0 ensures compatibility with SageAttention >= 2.2.0
# If 12.8.0 is not available, fallback to 12.6.3-cudnn-devel-ubuntu24.04
ARG BASE_IMAGE=nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage with sensible defaults for standalone builds
ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# PyTorch/CUDA Performance Optimizations for RTX 4090 and similar high-end GPUs
# These settings dramatically improve inference speed (can reduce processing time by 50-70%)
# Note: PYTORCH_CUDA_ALLOC_CONF is deprecated, using PYTORCH_ALLOC_CONF instead
ENV PYTORCH_ALLOC_CONF=max_split_size_mb:512
ENV TORCH_COMPILE_DEBUG=0
# Enable TF32 (TensorFloat-32) for Ada Lovelace (RTX 4090) - 2-3x faster with minimal accuracy loss
ENV TORCH_CUDNN_BENCHMARK=1
# cuDNN optimization - enables algorithm autotuning for faster convolutions
ENV CUDA_LAUNCH_BLOCKING=0
# Disable CUDA blocking for async execution
ENV MALLOC_ARENA_MAX=2
# Reduce memory fragmentation (useful for serverless)

# Global Python header paths for compilation (sageattention, latentsync, etc.)
# These make Python.h available to all subsequent compilations
ENV CFLAGS="-I/usr/include/python3.12"
ENV CPATH="/usr/include/python3.12"
ENV PYTHON_INCLUDE_DIR="/usr/include/python3.12"

# CUDA architecture list for compilation without GPU during build (serverless)
# Supported GPUs:
# - 8.9: L40, L40S, RTX 6000 Ada, RTX 4090 (Ada Lovelace) - PRIMARY TARGETS
# - 12.0: RTX 5090 (Blackwell) - requires CUDA 12.8+ and PyTorch 2.5+
# Additional architectures for compatibility:
# - 8.6: RTX A4000, A5000, A6000 (Ampere)
# - 8.0: A100 (Ampere datacenter)
# Note: For Ada Lovelace GPUs (L40, L40S, RTX 6000 Ada), we MUST include 8.9
# Note: For RTX 5090 (Blackwell), we include 12.0, but support may be limited in older PyTorch/sageattention versions
ARG TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;12.0"
ENV TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST}
ENV TRITON_CACHE_DIR=/tmp/triton_cache

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    build-essential \
    google-perftools \
    libtcmalloc-minimal4 \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install --no-cache-dir comfy-cli pip setuptools wheel

# Install ComfyUI
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Optionally install custom nodes via comfy-cli (registry)
# Usage example:
#   docker build --build-arg ENABLE_COMFY_NODE_INSTALL=true \
#                --build-arg COMFY_CUSTOM_NODES="comfyui-easy-use comfyui_essentials rgthree-comfy" \
#                -t my-img:tag .
ARG ENABLE_COMFY_NODE_INSTALL=false
ARG COMFY_CUSTOM_NODES="comfyui-easy-use comfyui_essentials rgthree-comfy"
RUN if [ "$ENABLE_COMFY_NODE_INSTALL" = "true" ]; then \
      echo "Installing custom nodes from registry: $COMFY_CUSTOM_NODES" && \
      comfy-node-install $COMFY_CUSTOM_NODES; \
    else \
      echo "Skipping comfy-node-install (ENABLE_COMFY_NODE_INSTALL=false)"; \
    fi

# Upgrade PyTorch if needed (for newer CUDA versions)
RUN if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi

# Change working directory to ComfyUI
WORKDIR /comfyui

# Make comfy-node-install available before installing nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Mandatory install of required custom nodes via comfy-cli (using registry names)
# See https://registry.comfy.org/ for correct node names
# Note: comfy-node-install uses registry names (often lowercase), which we'll rename later
RUN comfy-node-install \
    ComfyLiterals \
    comfyui-detail-daemon \
    comfyui-easy-use \
    comfyui-florence2 \
    comfyui-frame-interpolation \
    ComfyUI-GGUF \
    ComfyUI-GGUF-FantasyTalking \
    comfyui-impact-pack \
    comfyui-kjnodes \
    ComfyUI-LatentSyncWrapper \
    comfyui-logic \
    ComfyUI-Manager \
    comfyui-rmbg \
    comfyui-segment-anything-2 \
    ComfyUI-VibeVoice \
    comfyui-videohelpersuite \
    ComfyUI-WanAnimatePreprocess \
    ComfyUI-WanVideoWrapper \
    ComfyUI_Comfyroll_CustomNodes \
    comfyui_essentials \
    comfyui_layerstyle \
    ComfyUI_LayerStyle_Advance \
    ComfyUI_JPS-Nodes \
    comfyui_ultimatesdupscale \
    comfyui-custom-scripts \
    comfyui-image-selector \
    rgthree-comfy \
    was-node-suite-comfyui \
    cg-use-everywhere \
    comfy-plasma \
    comfyui_controlnet_aux \
    masquerade-nodes-comfyui \
    mikey_nodes

# Install nodes that need special handling (registry names or direct URLs)
RUN cd custom_nodes && \
    # RES4LYF - direct git clone
    git clone https://github.com/ClownsharkBatwing/RES4LYF.git RES4LYF || true && \
    # ComfyUI-TeaCache - registry name: teacache
    comfy-node-install teacache || true && \
    # cg-image-picker - direct GitHub URL (correct owner: chrisgoringe)
    git clone https://github.com/chrisgoringe/cg-image-picker.git cg-image-picker || true && \
    # HavocsCall_Custom_Nodes - registry name: havocscall_custom_nodes
    comfy-node-install havocscall_custom_nodes || true && \
    # DynamicPrompts - direct git clone (correct URL)
    git clone https://github.com/adieyal/comfyui-dynamicprompts.git comfyui-dynamicprompts || true

# Rename directories to match what ComfyUI expects
# comfy-node-install creates directories with registry names (often lowercase), but ComfyUI looks for real repo names
# Rename only if source exists and target doesn't exist (safe to run multiple times)
RUN set -e && \
    cd /comfyui/custom_nodes && \
    if [ -d "comfyui-detail-daemon" ] && [ ! -d "ComfyUI-Detail-Daemon" ]; then mv comfyui-detail-daemon ComfyUI-Detail-Daemon; fi && \
    if [ -d "comfyui-easy-use" ] && [ ! -d "ComfyUI-Easy-Use" ]; then mv comfyui-easy-use ComfyUI-Easy-Use; fi && \
    if [ -d "comfyui-florence2" ] && [ ! -d "ComfyUI-Florence2" ]; then mv comfyui-florence2 ComfyUI-Florence2; fi && \
    if [ -d "comfyui-frame-interpolation" ] && [ ! -d "ComfyUI-Frame-Interpolation" ]; then mv comfyui-frame-interpolation ComfyUI-Frame-Interpolation; fi && \
    if [ -d "comfyui-impact-pack" ] && [ ! -d "ComfyUI-Impact-Pack" ]; then mv comfyui-impact-pack ComfyUI-Impact-Pack; fi && \
    if [ -d "comfyui-kjnodes" ] && [ ! -d "ComfyUI-KJNodes" ]; then mv comfyui-kjnodes ComfyUI-KJNodes; fi && \
    if [ -d "comfyui-logic" ] && [ ! -d "ComfyUI-Logic" ]; then mv comfyui-logic ComfyUI-Logic; fi && \
    if [ -d "comfyui-rmbg" ] && [ ! -d "ComfyUI-RMBG" ]; then mv comfyui-rmbg ComfyUI-RMBG; fi && \
    if [ -d "comfyui-segment-anything-2" ] && [ ! -d "ComfyUI-segment-anything-2" ]; then mv comfyui-segment-anything-2 ComfyUI-segment-anything-2; fi && \
    if [ -d "comfyui-videohelpersuite" ] && [ ! -d "ComfyUI-VideoHelperSuite" ]; then mv comfyui-videohelpersuite ComfyUI-VideoHelperSuite; fi && \
    if [ -d "comfyui_layerstyle" ] && [ ! -d "ComfyUI_LayerStyle" ]; then mv comfyui_layerstyle ComfyUI_LayerStyle; fi && \
    if [ -d "comfyui_ultimatesdupscale" ] && [ ! -d "ComfyUI_UltimateSDUpscale" ]; then mv comfyui_ultimatesdupscale ComfyUI_UltimateSDUpscale; fi && \
    if [ -d "comfyui_essentials" ] && [ ! -d "ComfyUI_essentials" ]; then mv comfyui_essentials ComfyUI_essentials; fi && \
    if [ -d "havocscall_custom_nodes" ] && [ ! -d "comfyui_HavocsCall_Custom_Nodes" ]; then mv havocscall_custom_nodes comfyui_HavocsCall_Custom_Nodes; fi && \
    if [ -d "teacache" ] && [ ! -d "ComfyUI-TeaCache" ]; then mv teacache ComfyUI-TeaCache; fi && \
    echo "Directory renaming completed" && \
    ls -la | head -20

# Copy custom nodes from project directory (optional - will be overridden by Network Volume if available)
# Set SKIP_NODE_INSTALL=true to skip installation during build
ARG SKIP_NODE_INSTALL=false
COPY --chown=root:root custom_nodes custom_nodes

# Install dependencies for custom nodes (optimized - installs in parallel where possible)
RUN if [ "$SKIP_NODE_INSTALL" = "true" ]; then \
      echo "Skipping custom nodes installation (will use Network Volume)"; \
      rm -rf custom_nodes && mkdir -p custom_nodes; \
    else \
      echo "Installing dependencies for custom_nodes from project"; \
      # Collect all requirements.txt files (any depth) first, then install in batch for better caching
      find custom_nodes -name "requirements.txt" -type f 2>/dev/null -exec echo "Found: {}" \; && \
      find custom_nodes -name "requirements.txt" -type f 2>/dev/null | \
        xargs -I {} uv pip install --no-cache-dir -r {} || true; \
      # Install common dependencies that might be needed
      uv pip install --no-cache-dir segment-anything-2 || true; \
      uv pip install --no-cache-dir rembg || true; \
    fi

# Install sageattention for CUDA kernel optimization (required by ComfyUI-KJNodes)
# This is installed regardless of SKIP_NODE_INSTALL since it is needed at runtime
# Note: Installation may take 30-40 minutes due to CUDA kernel compilation
# If build hangs here, it's normal - just wait. The installation will complete.
# We also install it at runtime as a fallback (see CMD below)
# Requirements:
# - CUDA devel image (provides nvcc, CUDA_HOME, headers)
# - CFLAGS/CPATH set globally (already done above)
# - TORCH_CUDA_ARCH_LIST set globally (already done above)
# - SageAttention 2.2.0 requires PyTorch >= 2.1.1 (should be compatible with CUDA 12.8)
# - --no-build-isolation allows using already installed PyTorch and CUDA toolkit
ARG SKIP_SAGEATTENTION=false
RUN if [ "$SKIP_SAGEATTENTION" != "true" ]; then \
        echo "Installing sageattention 2.2.0 (this may take 30-40 minutes due to CUDA compilation)..." && \
        echo "Base image: devel variant (provides CUDA_HOME, nvcc)" && \
        echo "Compiling for GPU architectures: ${TORCH_CUDA_ARCH_LIST}" && \
        echo "Python headers: CFLAGS=${CFLAGS}, CPATH=${CPATH}" && \
        echo "CRITICAL: Must include 8.9 (Ada Lovelace: L40, L40S, RTX 6000 Ada, RTX 4090) and 12.0 (Blackwell: RTX 5090) in TORCH_CUDA_ARCH_LIST" && \
        export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST}" && \
        export TRITON_CACHE_DIR=/tmp/triton_cache && \
        timeout 2400 uv pip install --no-cache-dir sageattention==2.2.0 --no-build-isolation || \
        timeout 2400 pip install --no-cache-dir sageattention==2.2.0 --no-build-isolation || \
        (echo "sageattention installation failed during build, will retry at runtime" && true); \
    else \
        echo "Skipping sageattention installation during build (will install at runtime)"; \
    fi

# Go back to the root
WORKDIR /

# Support for the network volume
ADD src/extra_model_paths.yaml /comfyui/extra_model_paths.yaml

# Install Python runtime dependencies for the handler
RUN uv pip install --no-cache-dir runpod requests websocket-client

# Add application code and scripts
ADD src/start.sh src/optimize_pytorch.py handler.py test_input.json ./
RUN chmod +x /start.sh && chmod +x /optimize_pytorch.py

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Stage 2: Download models
FROM base AS downloader

ARG HUGGINGFACE_ACCESS_TOKEN
# Set default model type if none is provided
ARG MODEL_TYPE=flux1-dev-fp8

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories upfront
RUN mkdir -p models/checkpoints models/vae models/unet models/clip

# Stage 3: Final image (this is the default target stage)
FROM base AS final

# Copy models from stage 2 to the final image (optional - models can be in Network Volume)
COPY --from=downloader /comfyui/models /comfyui/models

# Ensure all necessary files and scripts are in place
# These should already be copied in base stage, but we verify
WORKDIR /

# Set the default command to run when starting the container
# Install sageattention at runtime if not already installed during build
# CFLAGS, CPATH, and TORCH_CUDA_ARCH_LIST are already set globally via ENV above
# CRITICAL: TORCH_CUDA_ARCH_LIST must include:
# - 8.9 for Ada Lovelace (L40, L40S, RTX 6000 Ada, RTX 4090)
# - 12.0 for Blackwell (RTX 5090)
# Use --no-build-isolation for consistency with build-time installation
CMD ["bash", "-c", "export TORCH_CUDA_ARCH_LIST=\"${TORCH_CUDA_ARCH_LIST:-8.0;8.6;8.9;12.0}\" && export TRITON_CACHE_DIR=/tmp/triton_cache && echo \"Runtime sageattention install: compiling for ${TORCH_CUDA_ARCH_LIST}\" && (uv pip install --no-cache-dir sageattention==2.2.0 --no-build-isolation || pip install --no-cache-dir sageattention==2.2.0 --no-build-isolation || python3 -m pip install --no-cache-dir sageattention==2.2.0 --no-build-isolation || echo \"Warning: sageattention installation failed, continuing anyway...\") && /start.sh"]
