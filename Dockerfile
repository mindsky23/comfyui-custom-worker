# ============================================================
# ComfyUI + Runpod handler — production Dockerfile
# Slim final image, no baked models, fast push
# CUDA 12.4 (matches PyTorch cu124 wheels)
# ============================================================

# ---------- [builder] heavy image (compilers & headers) ----------
  FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu24.04 AS builder

  ARG DEBIAN_FRONTEND=noninteractive
  # PyTorch wheels index for CUDA 12.4
  ARG PYTORCH_INDEX_URL="https://download.pytorch.org/whl/cu124"
  # Optional: install/skip sageattention (true/false)
  ARG SKIP_SAGEATTENTION="false"
  # Optional: install a list of custom nodes (space- or newline-separated git URLs)
  ARG CUSTOM_NODES=""
  # Architectures to compile native CUDA extensions for (edit if needed)
  ARG TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9"
  
  ENV TZ=Etc/UTC \
      LANG=C.UTF-8 \
      LC_ALL=C.UTF-8 \
      PIP_NO_CACHE_DIR=1 \
      PATH="/opt/venv/bin:${PATH}" \
      CUDA_HOME="/usr/local/cuda" \
      TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST}"
  
  # Base deps (build + runtime needed by ComfyUI)
  RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-dev python3-pip \
        git ca-certificates curl wget \
        build-essential ninja-build pkg-config \
        libgl1 libglib2.0-0 ffmpeg \
      && rm -rf /var/lib/apt/lists/*
  
  # Create venv
  RUN python3 -m venv /opt/venv && \
      python -m pip install --upgrade pip wheel setuptools
  
  # Install PyTorch (CUDA 12.4 wheels)
  RUN python -m pip install --no-cache-dir --index-url "${PYTORCH_INDEX_URL}" \
        torch torchvision torchaudio
  
  # ---- ComfyUI ----
  WORKDIR /comfyui
  RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git . 
  
  # ComfyUI deps
  RUN python -m pip install --no-cache-dir -r requirements.txt
  
  # Optional: popular extras that many handlers expect
  RUN python -m pip install --no-cache-dir websocket-client requests pillow numpy
  
  # Optional: build/install SageAttention in builder so .so попадёт в venv
  RUN if [ "${SKIP_SAGEATTENTION}" != "true" ]; then \
        python -m pip install -U ninja && \
        python -m pip install --no-cache-dir --no-build-isolation "sageattention>=2.2.0"; \
      else \
        echo "Skipping sageattention build"; \
      fi
  
  # Optional: custom nodes (each entry is a git URL). Empty by default.
  RUN set -euo pipefail; \
      if [ -n "${CUSTOM_NODES}" ]; then \
        mkdir -p /comfyui/custom_nodes; \
        echo "${CUSTOM_NODES}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk 'NF' | while read -r url; do \
          name="$(basename "${url}" .git)"; \
          echo "Cloning custom node: ${url} -> ${name}"; \
          git clone --depth=1 "${url}" "/comfyui/custom_nodes/${name}"; \
        done; \
        # Try to install extra requirements per-node if present
        find /comfyui/custom_nodes -maxdepth 2 -type f -iname 'requirements.txt' -print0 \
          | xargs -0 -I{} sh -c 'echo Installing deps from {}; python -m pip install --no-cache-dir -r "{}" || true'; \
      fi
  
  # Minimal extra_model_paths.yaml (models mounted at runtime)
  RUN mkdir -p /comfyui && \
      printf "ComfyUI:\n  base_path: /comfyui\n  models_dir: /comfyui/models\nExtra:\n  - /models\n" > /comfyui/extra_model_paths.yaml
  
  # Your Runpod handler (must exist in build context)
  WORKDIR /app
  COPY handler.py /app/handler.py
  
  # Create start script: start ComfyUI, wait readiness, then run handler
  RUN bash -lc 'cat > /start.sh << "EOF"\n\
  #!/usr/bin/env bash\n\
  set -euo pipefail\n\
  export PYTHONUNBUFFERED=1\n\
  export PATH=\"/opt/venv/bin:${PATH}\"\n\
  cd /comfyui\n\
  # Start ComfyUI (0.0.0.0:8188)\n\
  python -u main.py --listen 0.0.0.0 --port 8188 &\n\
  COMFY_PID=$!\n\
  # Wait HTTP ready (max 180s)\n\
  for i in $(seq 1 180); do\n\
    if curl -fsS http://127.0.0.1:8188/ >/dev/null; then break; fi\n\
    sleep 1\n\
  done\n\
  cd /app\n\
  exec python -u /app/handler.py\n\
  EOF\n\
  chmod +x /start.sh'
  
  # ---------- [final] slim runtime (no compilers) ----------
  FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu24.04 AS final
  
  ARG DEBIAN_FRONTEND=noninteractive
  ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 \
      PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 \
      PATH="/opt/venv/bin:${PATH}"
  
  # Runtime libs only
  RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv git ca-certificates curl \
        libgl1 libglib2.0-0 ffmpeg \
      && rm -rf /var/lib/apt/lists/*
  
  # Copy runtime artifacts from builder
  COPY --from=builder /opt/venv /opt/venv
  COPY --from=builder /comfyui /comfyui
  COPY --from=builder /app /app
  COPY --from=builder /start.sh /start.sh
  
  # Models live outside the image (mount as volumes)
  VOLUME ["/comfyui/models", "/models"]
  
  WORKDIR /
  EXPOSE 8188
  
  # Healthcheck for ComfyUI HTTP
  HEALTHCHECK --interval=30s --timeout=5s --retries=20 CMD curl -fsS http://127.0.0.1:8188/ || exit 1
  
  CMD ["/start.sh"]