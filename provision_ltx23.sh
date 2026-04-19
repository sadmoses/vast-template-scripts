#!/usr/bin/env bash
set -euo pipefail

# Vast template auto-provision script for the current working
# ComfyUI + built-in LTX-2.3 text-to-video setup.
# Secrets such as HF_TOKEN should be passed in as template
# environment variables, not hard-coded into this file.

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
COMFYUI_DIR="${WORKSPACE_DIR}/ComfyUI"
VENV_DIR="${WORKSPACE_DIR}/comfy-env"
LOG_FILE="${WORKSPACE_DIR}/provision_ltx23.log"
COMFY_LOG="${WORKSPACE_DIR}/comfyui.log"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "[provision] starting LTX-2.3 setup"

if [[ -n "${HF_TOKEN:-}" ]]; then
  echo "[provision] HF_TOKEN detected"
else
  echo "[provision] HF_TOKEN not set; public downloads may still work, but authenticated downloads are safer"
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y git ffmpeg python3 python3-venv python3-pip python-is-python3

cd "${WORKSPACE_DIR}"

if [[ ! -d "${VENV_DIR}" ]]; then
  python3 -m venv "${VENV_DIR}"
fi

source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip setuptools wheel
python -m pip install torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 --index-url https://download.pytorch.org/whl/cu128
python -m pip install -U huggingface_hub hf_xet

if [[ ! -d "${COMFYUI_DIR}" ]]; then
  git clone https://github.com/Comfy-Org/ComfyUI.git "${COMFYUI_DIR}"
fi

cd "${COMFYUI_DIR}"

python -m pip install -r requirements.txt
python -m pip install -r manager_requirements.txt

mkdir -p "${COMFYUI_DIR}/models/checkpoints/LTX-Video"
mkdir -p "${COMFYUI_DIR}/models/checkpoints"
mkdir -p "${COMFYUI_DIR}/models/diffusion_models"
mkdir -p "${COMFYUI_DIR}/models/latent_upscale_models"
mkdir -p "${COMFYUI_DIR}/models/loras"
mkdir -p "${COMFYUI_DIR}/models/text_encoders"
mkdir -p "${COMFYUI_DIR}/models/vae"

hf download Lightricks/LTX-2.3-fp8 ltx-2.3-22b-dev-fp8.safetensors --local-dir "${COMFYUI_DIR}/models/checkpoints/LTX-Video"
hf download Lightricks/LTX-2.3 ltx-2.3-22b-distilled-lora-384.safetensors --local-dir "${COMFYUI_DIR}/models/loras"
hf download Lightricks/LTX-2.3 ltx-2.3-spatial-upscaler-x2-1.1.safetensors --local-dir "${COMFYUI_DIR}/models/latent_upscale_models"
hf download Comfy-Org/ltx-2 split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors --local-dir "${COMFYUI_DIR}/models/text_encoders"

# FLUX.1 Krea Dev additions for strong local image generation and better
# reference-image creation for future image-to-video workflows.
hf download black-forest-labs/FLUX.1-Krea-dev flux1-krea-dev_fp8_scaled.safetensors --local-dir "${COMFYUI_DIR}/models/diffusion_models"
hf download comfyanonymous/flux_text_encoders clip_l.safetensors --local-dir "${COMFYUI_DIR}/models/text_encoders"
hf download comfyanonymous/flux_text_encoders t5xxl_fp16.safetensors --local-dir "${COMFYUI_DIR}/models/text_encoders"
hf download comfyanonymous/flux_text_encoders t5xxl_fp8_e4m3fn.safetensors --local-dir "${COMFYUI_DIR}/models/text_encoders"
hf download black-forest-labs/FLUX.1-dev ae.safetensors --local-dir "${COMFYUI_DIR}/models/vae"

mv "${COMFYUI_DIR}/models/text_encoders/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors" "${COMFYUI_DIR}/models/text_encoders/"
rm -rf "${COMFYUI_DIR}/models/text_encoders/split_files"

cp "${COMFYUI_DIR}/models/checkpoints/LTX-Video/ltx-2.3-22b-dev-fp8.safetensors" "${COMFYUI_DIR}/models/checkpoints/"

pkill -f "python main.py --listen 0.0.0.0 --port 8188 --enable-manager" || true
nohup python main.py --listen 0.0.0.0 --port 8188 --enable-manager > "${COMFY_LOG}" 2>&1 &

echo "[provision] done"
echo "[provision] open Vast IP/Ports and use the public port mapped to 8188/tcp"
