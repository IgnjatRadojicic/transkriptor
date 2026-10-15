#!/usr/bin/env python3
"""Skida modele koje transkriptor koristi u HF_HOME.

transkriptor.sh je sam poziva pre transkripcije (sa --tiho), pa ne mora rucno.
Rucno:
  WSL:    HF_HOME=... ~/whisperx-env/bin/python alati/skini-modele.py [--model large-v3-turbo]
  Docker: docker compose run --rm --entrypoint python transkriptor /app/alati/skini-modele.py

Ono sto vec postoji se preskace. Pyannote model trazi HF_TOKEN i prihvacene uslove na
https://huggingface.co/pyannote/speaker-diarization-community-1
"""
import argparse
import os
import sys
import time

arg = argparse.ArgumentParser()
arg.add_argument("--tiho", action="store_true", help="nista ne ispisuj ako su modeli vec tu")
arg.add_argument("--model", default=os.environ.get("MODEL", "large-v3-turbo"), help="Whisper model kao u MODEL")
ARG = arg.parse_args()
TIHO = ARG.tiho
# skripta mora na internet bez obzira na .env
os.environ["HF_HUB_OFFLINE"] = "0"

from faster_whisper.utils import _MODELS  # noqa: E402
from huggingface_hub import snapshot_download  # noqa: E402
from huggingface_hub.errors import GatedRepoError, HfHubHTTPError, LocalEntryNotFoundError  # noqa: E402

# "large-v3-turbo" -> "mobiuslabsgmbh/faster-whisper-large-v3-turbo", isto kao sto radi WhisperX
WHISPER = _MODELS.get(ARG.model, ARG.model)
MODELI = [
    # (repo, sta je, treba token)
    (WHISPER, f"Whisper {ARG.model}, govor u tekst", False),
    ("pyannote/speaker-diarization-community-1", "pyannote, ko govori", True),
]
TOKEN = os.environ.get("HF_TOKEN") or None


def skini(repo, treba_token, javi):
    if os.path.isdir(repo):  # MODEL moze biti i lokalni folder
        return "vec postoji"
    try:
        snapshot_download(repo, local_files_only=True)
        return "vec postoji"
    except LocalEntryNotFoundError:
        pass
    javi()
    if treba_token and not TOKEN:
        return "FALI HF_TOKEN u .env"
    for pokusaj in range(1, 6):
        try:
            snapshot_download(repo, token=TOKEN)
            return "skinuto"
        except GatedRepoError:
            return "nemas pristup, prihvati uslove na huggingface.co/" + repo
        except HfHubHTTPError as e:
            status = getattr(e.response, "status_code", None)
            if status in (401, 403, 404):  # los token ili pogresno ime, ponavljanje ne pomaze
                return f"HTTP {status}, proveri HF_TOKEN i ime modela"
            print(f"  pokusaj {pokusaj} nije uspeo: {e}", file=sys.stderr)
            time.sleep(5 * pokusaj)
        except Exception as e:  # mreza ume da stane na pola, pa probaj ponovo
            print(f"  pokusaj {pokusaj} nije uspeo: {e}", file=sys.stderr)
            time.sleep(5 * pokusaj)
    return "NIJE USPELO posle 5 pokusaja"


def main():
    # sa --tiho se nista ne ispisuje dok god su svi modeli vec tu
    ispis = (lambda s: print(s, file=sys.stderr, flush=True)) if TIHO else print
    folder = os.environ.get("HF_HOME", "~/.cache/huggingface")
    if not TIHO:
        print(f"Modeli: {folder}")
    los = skinuto = False
    for repo, opis, treba_token in MODELI:
        rezultat = skini(repo, treba_token, lambda: ispis(f"- {opis}: skidam u {folder} ..."))
        if rezultat != "vec postoji" or not TIHO:
            ispis(f"- {opis} ({repo}): {rezultat}")
        skinuto |= rezultat == "skinuto"
        los |= rezultat not in ("vec postoji", "skinuto")
    # VAD model dolazi uz whisperx paket i ne skida se posebno
    if los:
        sys.exit(1)
    if skinuto or not TIHO:
        ispis("Modeli su spremni.")


if __name__ == "__main__":
    main()
