# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

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
    && ln -sf /usr/bin/python3.12 /usr/bin/python
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
RUN uv pip install --no-cache-dir sageattention || true

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install --no-cache-dir runpod requests websocket-client

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Set the default command to run when starting the container
CMD ["bash", "-c", "uv pip install --no-cache-dir sageattention || pip install --no-cache-dir sageattention || true && /start.sh"]

# Stage 2: Download models
FROM base AS downloader

ARG HUGGINGFACE_ACCESS_TOKEN
# Set default model type if none is provided
ARG MODEL_TYPE=flux1-dev-fp8

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories upfront
RUN mkdir -p models/checkpoints models/vae models/unet models/clip

# Stage 3: Final image
FROM base AS final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models
