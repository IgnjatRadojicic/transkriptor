#!/usr/bin/env bash
# Instalacija bez Dockera, za WSL (Debian/Ubuntu) sa NVIDIA grafickom.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

sudo apt-get update
sudo apt-get install -y ffmpeg python3 python3-venv

python3 -m venv ~/whisperx-env
# /tmp je na Debianu u RAM-u (~4 GB) i PyTorch ne stane, zato temp ide na disk
mkdir -p ~/pip-tmp
TMPDIR=~/pip-tmp ~/whisperx-env/bin/pip install --resume-retries 20 whisperx==3.8.6
rm -rf ~/pip-tmp

mkdir -p ~/.local/bin
ln -sf "$ROOT/transkriptor.sh" ~/.local/bin/transkriptor
chmod +x "$ROOT/transkriptor.sh"
echo "Gotovo. Pokreni: transkriptor snimak.m4a"
