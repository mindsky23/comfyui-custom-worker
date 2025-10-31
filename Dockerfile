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
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

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

# Mandatory install of required custom nodes via comfy-cli (registry or URLs)
RUN comfy-node-install \
    https://github.com/ltdrdata/ComfyLiterals \
    https://github.com/pythongosssss/ComfyUI-Detail-Daemon \
    https://github.com/wasdennnoch/ComfyUI-Easy-Use \
    https://github.com/Fannovel16/comfyui-frame-interpolation \
    https://github.com/pythongosssss/ComfyUI-GGUF \
    https://github.com/FantasyTalking/ComfyUI-GGUF-FantasyTalking \
    https://github.com/ltdrdata/ComfyUI-Impact-Pack \
    https://github.com/kijai/ComfyUI-KJNodes \
    https://github.com/JonVeg/ComfyUI-LatentSyncWrapper \
    https://github.com/pythongosssss/ComfyUI-Logic \
    https://github.com/ltdrdata/ComfyUI-Manager \
    https://github.com/biegert/ComfyUI-RMBG \
    https://github.com/adelelhedi/ComfyUI-segment-anything-2 \
    https://github.com/pythongosssss/ComfyUI-TeaCache \
    https://github.com/VibeVoice/ComfyUI-VibeVoice \
    https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite \
    https://github.com/Wan-Animate/ComfyUI-WanAnimatePreprocess \
    https://github.com/Wan-Animate/ComfyUI-WanVideoWrapper \
    https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes \
    https://github.com/cubiq/ComfyUI_essentials \
    https://github.com/Fannovel16/ComfyUI_LayerStyle \
    https://github.com/Fannovel16/ComfyUI_LayerStyle_Advance \
    https://github.com/jags111/ComfyUI_JPS-Nodes \
    https://github.com/ssitu/ComfyUI_UltimateSDUpscale \
    https://github.com/RES4LYF/ComfyUI-RES4LYF \
    https://github.com/pythongosssss/comfyui-custom-scripts \
    https://github.com/adieyal/comfyui-dynamicprompts \
    https://github.com/pythongosssss/comfyui-image-selector \
    https://github.com/rgthree/rgthree-comfy \
    https://github.com/oneoffcoder/comfyui-havocs-call-custom-nodes \
    https://github.com/wasdennnoch/was-node-suite-comfyui \
    https://github.com/cg-use-everywhere/cg-image-picker \
    https://github.com/cg-use-everywhere/cg-use-everywhere \
    https://github.com/rgtjf/comfy-plasma \
    https://github.com/Fannovel16/comfyui_controlnet_aux \
    https://github.com/BadCafeCode/masquerade-nodes-comfyui \
    https://github.com/bash-j/mikey_nodes

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
CMD ["/start.sh"]

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