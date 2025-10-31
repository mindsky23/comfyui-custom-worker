# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

FROM ${BASE_IMAGE} AS base

ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

RUN apt-get update && apt-get install -y \
    python3.12 python3.12-venv git wget libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

ENV PATH="/opt/venv/bin:${PATH}"

RUN uv pip install comfy-cli pip setuptools wheel

RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

RUN if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi

WORKDIR /comfyui
ADD src/extra_model_paths.yaml ./
WORKDIR /

RUN uv pip install runpod requests websocket-client

ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

CMD ["/start.sh"]

# --- Models stage (оставляем как было) ---
FROM base AS downloader
ARG HUGGINGFACE_ACCESS_TOKEN
ARG MODEL_TYPE=flux1-dev-fp8
WORKDIR /comfyui
RUN mkdir -p models/checkpoints models/vae models/unet models/clip

# скачивание моделей можно оставить как есть или удалить

# --- Финальный образ ---
FROM base AS final

COPY --from=downloader /comfyui/models /comfyui/models

# 👇 вот эта строка — ключевая: добавляем твои кастомные ноды прямо в образ
COPY /workspace/ComfyUI/custom_nodes /comfyui/custom_nodes

# остальное не трогаем