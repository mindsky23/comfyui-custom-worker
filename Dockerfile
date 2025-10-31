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
RUN uv pip install comfy-cli pip setuptools wheel

# Install ComfyUI
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Upgrade PyTorch if needed (for newer CUDA versions)
RUN if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install custom nodes (optional - will be overridden by Network Volume if available)
# Set SKIP_NODE_INSTALL=true to skip installation during build
ARG SKIP_NODE_INSTALL=false
RUN if [ "$SKIP_NODE_INSTALL" != "true" ]; then \
      mkdir -p custom_nodes && \
      cd custom_nodes && \
      git clone https://github.com/ltdrdata/ComfyLiterals.git || true && \
      git clone https://github.com/pythongosssss/ComfyUI-Detail-Daemon.git || true && \
      git clone https://github.com/wasdennnoch/ComfyUI-Easy-Use.git || true && \
      git clone https://github.com/Fannovel16/comfyui-frame-interpolation.git ComfyUI-Frame-Interpolation || true && \
      git clone https://github.com/pythongosssss/ComfyUI-GGUF.git || true && \
      git clone https://github.com/FantasyTalking/ComfyUI-GGUF-FantasyTalking.git || true && \
      git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git || true && \
      git clone https://github.com/kijai/ComfyUI-KJNodes.git || true && \
      git clone https://github.com/JonVeg/ComfyUI-LatentSyncWrapper.git || true && \
      git clone https://github.com/pythongosssss/ComfyUI-Logic.git || true && \
      git clone https://github.com/ltdrdata/ComfyUI-Manager.git || true && \
      git clone https://github.com/biegert/ComfyUI-RMBG.git || true && \
      git clone https://github.com/adelelhedi/ComfyUI-segment-anything-2.git || true && \
      git clone https://github.com/pythongosssss/ComfyUI-TeaCache.git || true && \
      git clone https://github.com/VibeVoice/ComfyUI-VibeVoice.git || true && \
      git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git || true && \
      git clone https://github.com/Wan-Animate/ComfyUI-WanAnimatePreprocess.git || true && \
      git clone https://github.com/Wan-Animate/ComfyUI-WanVideoWrapper.git || true && \
      git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git || true && \
      git clone https://github.com/cubiq/ComfyUI_essentials.git || true && \
      git clone https://github.com/Fannovel16/ComfyUI_LayerStyle.git || true && \
      git clone https://github.com/Fannovel16/ComfyUI_LayerStyle_Advance.git || true && \
      git clone https://github.com/jags111/ComfyUI_JPS-Nodes.git || true && \
      git clone https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git || true && \
      git clone https://github.com/RES4LYF/ComfyUI-RES4LYF.git RES4LYF || true && \
      git clone https://github.com/pythongosssss/comfyui-custom-scripts.git || true && \
      git clone https://github.com/adieyal/comfyui-dynamicprompts.git || true && \
      git clone https://github.com/pythongosssss/comfyui-image-selector.git || true && \
      git clone https://github.com/rgthree/rgthree-comfy.git || true && \
      git clone https://github.com/oneoffcoder/comfyui-havocs-call-custom-nodes.git comfyui_HavocsCall_Custom_Nodes || true && \
      git clone https://github.com/wasdennnoch/was-node-suite-comfyui.git || true && \
      git clone https://github.com/cg-use-everywhere/cg-image-picker.git || true && \
      git clone https://github.com/cg-use-everywhere/cg-use-everywhere.git || true && \
      git clone https://github.com/rgtjf/comfy-plasma.git || true && \
      git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git || true && \
      git clone https://github.com/BadCafeCode/masquerade-nodes-comfyui.git || true && \
      git clone https://github.com/bash-j/mikey_nodes.git || true && \
      cd /comfyui && \
      find custom_nodes -maxdepth 2 -name "requirements.txt" -type f | while read req; do \
        echo "Installing dependencies from $req"; \
        uv pip install -r "$req" || true; \
      done && \
      uv pip install segment-anything-2 || true && \
      uv pip install rembg || true; \
    else \
      echo "Skipping custom nodes installation (will use Network Volume)"; \
      mkdir -p custom_nodes; \
    fi

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

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