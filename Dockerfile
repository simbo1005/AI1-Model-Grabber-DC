# syntax=docker/dockerfile:1.7

ARG RUNPOD_COMFY_IMAGE=runpod/comfyui@sha256:7078f94dbe28d079c487c245dc3524443e2c6225a6208a1fff8c7a652c1b3a40
FROM ${RUNPOD_COMFY_IMAGE}

ARG IMAGE_VERSION=dev
ARG HF_TOKEN_REVISION=local
ARG REQUIRE_HF_DOWNLOAD_TOKEN=0

LABEL org.opencontainers.image.title="dsnn ComfyUI Workflow Launcher" \
      org.opencontainers.image.description="Stock RunPod ComfyUI plus the remotely updateable dsnn Model Grabber" \
      org.opencontainers.image.source="https://github.com/simbo1005/AI1-Model-Grabber-DC" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

USER root
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LAUNCHER_PORT=3000 \
    LAUNCHER_AUTO_UPDATE=1 \
    LAUNCHER_GITHUB_REPO=simbo1005/AI1-Model-Grabber-DC \
    LAUNCHER_GITHUB_REF=main \
    COMFYUI_DIR=/workspace/runpod-slim/ComfyUI \
    HF_XET_HIGH_PERFORMANCE=1 \
    HF_TOKEN_FILE=/opt/dsnn/secrets/hf_token

WORKDIR /opt/dsnn

RUN if ! command -v wget >/dev/null 2>&1; then \
      apt-get update \
      && apt-get install -y --no-install-recommends wget \
      && rm -rf /var/lib/apt/lists/*; \
    fi

COPY requirements-launcher.txt /tmp/requirements-launcher.txt
RUN python3.12 -m pip install \
      --break-system-packages \
      --no-cache-dir \
      -r /tmp/requirements-launcher.txt \
    && rm /tmp/requirements-launcher.txt \
    && mv /start.sh /usr/local/bin/runpod-base-start.sh \
    && chmod +x /usr/local/bin/runpod-base-start.sh

# Warm the dependencies shared by the pinned custom nodes.  The constraints are
# captured from the RunPod base image so this layer cannot replace its CUDA Torch
# build with a CPU wheel.  Node requirements still run at install time as a safe
# fallback when a catalog entry changes.
COPY docker/custom-node-requirements.txt /tmp/custom-node-requirements.txt
RUN set -eu; \
    python3.12 -m pip freeze \
      | grep -iE '^(torch|torchvision|torchaudio|numpy|transformers|pillow|opencv-[a-z-]+)==' \
      > /tmp/dsnn-constraints.txt; \
    python3.12 -m pip install --break-system-packages --no-cache-dir \
      -c /tmp/dsnn-constraints.txt -r /tmp/custom-node-requirements.txt; \
    expected="$(sed -n 's/^[Tt]orch==//p' /tmp/dsnn-constraints.txt)"; \
    actual="$(python3.12 -c 'import torch; print(torch.__version__)')"; \
    test -n "$expected"; \
    test "$actual" = "$expected"; \
    rm /tmp/custom-node-requirements.txt /tmp/dsnn-constraints.txt

# dlib is source-only and is required by ComfyUI_FaceAnalysis.  Build it once
# here instead of making a rented Pod compile C++ during a workflow install.
RUN set -eu; \
    added_toolchain=0; \
    if ! command -v c++ >/dev/null 2>&1; then \
      apt-get update; apt-get install -y --no-install-recommends build-essential; added_toolchain=1; \
    fi; \
    export MAKEFLAGS=-j4 CMAKE_BUILD_PARALLEL_LEVEL=4; \
    python3.12 -m pip install --break-system-packages --no-cache-dir cmake 'dlib==20.0.1'; \
    python3.12 -c 'import dlib; print(dlib.__version__)'; \
    python3.12 -m pip uninstall -y cmake; \
    if [ "$added_toolchain" = 1 ]; then apt-get purge -y build-essential && apt-get autoremove -y; fi; \
    rm -rf /var/lib/apt/lists/*

COPY launcher/ /opt/dsnn/launcher/
COPY catalog/ /opt/dsnn/catalog/
COPY docker/entrypoint.sh /start.sh
RUN --mount=type=secret,id=hf_download_token \
    set -eu; \
    chmod +x /start.sh; \
    install -d -m 0700 /opt/dsnn/secrets; \
    if [ -s /run/secrets/hf_download_token ]; then \
      grep -q '^hf_' /run/secrets/hf_download_token; \
      install -m 0400 \
        /run/secrets/hf_download_token \
        /opt/dsnn/secrets/hf_token; \
    fi; \
    if [ "${REQUIRE_HF_DOWNLOAD_TOKEN}" = "1" ] \
       && [ ! -s /opt/dsnn/secrets/hf_token ]; then \
      echo "Required Hugging Face download credential was not supplied."; \
      exit 1; \
    fi; \
    printf '%s' "${HF_TOKEN_REVISION}" > /opt/dsnn/secrets/.revision

WORKDIR /workspace/runpod-slim

EXPOSE 3000 8188 8888

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:3000/api/health || exit 1

ENTRYPOINT ["/start.sh"]
