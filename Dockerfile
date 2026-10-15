FROM python:3.13-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg nodejs npm \
 && rm -rf /var/lib/apt/lists/*

# WhisperX povlaci PyTorch sa CUDA bibliotekama (~4 GB)
RUN pip install --no-cache-dir whisperx==3.8.6
# Claude CLI zakljucan na verziju da novi build ne promeni ponasanje. Nova: --build-arg CLAUDE_VERSION=...
ARG CLAUDE_VERSION=2.1.300
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION}

WORKDIR /app
COPY transkriptor.sh ./
COPY prompts ./prompts
COPY alati/skini-modele.py ./alati/
RUN chmod +x transkriptor.sh

# LANG: bez njega wc -m broji bajtove pa su š, č, ć, ž, đ po dva znaka
ENV WHISPERX=whisperx \
    HF_HOME=/modeli \
    LANG=C.UTF-8 \
    DISABLE_AUTOUPDATER=1 \
    PYTHONUNBUFFERED=1

WORKDIR /snimci
ENTRYPOINT ["/app/transkriptor.sh"]
