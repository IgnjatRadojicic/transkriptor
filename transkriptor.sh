#!/usr/bin/env bash
# transkriptor: snimak govora -> transkript (WhisperX, lokalno) -> beleske (Claude)
#
# Upotreba:
#   transkriptor.sh [opcije] deo1.m4a [deo2.m4a ...]
# Svi fajlovi su delovi JEDNOG snimka i spajaju se u jedne beleske.
#
# Opcije:
#   -n IME     ime fajla sa beleskama (default: ime prvog snimka)
#   -o FOLDER  gde idu beleske (default: pored snimka)
#   -t         preskoci transkripciju ako .txt vec postoji
#   -b         samo transkript, bez beleski
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

log() { printf '\033[1;34m[transkriptor]\033[0m %s\n' "$*" >&2; }
greska() { log "$*"; exit 1; }

# .env se cita kao KEY=vrednost (isto kao Docker env_file), bez izvrsavanja koda.
# Promenljiva koja je vec postavljena u okruzenju ima prednost nad .env.
ucitaj_env() {
  local red k v
  while IFS= read -r red || [ -n "$red" ]; do
    red="${red%$'\r'}"  # .env sacuvan u Notepadu ima CRLF
    [[ "$red" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    k="${BASH_REMATCH[1]}" ; v="${BASH_REMATCH[2]}"
    if [[ "$v" =~ ^\"(.*)\"$ || "$v" =~ ^\'(.*)\'$ ]]; then v="${BASH_REMATCH[1]}"
    else v="${v%%[[:space:]]#*}"; fi
    [ -n "${!k+x}" ] || export "$k=$v"
  done < "$1"
}
[ -f "$ROOT/.env" ] && ucitaj_env "$ROOT/.env"

# Podesavanja
WHISPERX="${WHISPERX:-$HOME/whisperx-env/bin/whisperx}"
# modeli: HF_HOME iz .env, inace standardni HF kes (u Dockeru je uvek /modeli)
export HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"
export HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-1}"
JEZIK="${JEZIK:-sr}"
MODEL="${MODEL:-large-v3-turbo}"
CLAUDE_MODEL="${CLAUDE_MODEL:-sonnet}"

ime="" ; izlaz="" ; preskoci=0 ; bez_beleski=0
while getopts "n:o:tb" opt; do
  case $opt in
    n) ime="$OPTARG" ;;
    o) izlaz="$OPTARG" ;;
    t) preskoci=1 ;;
    b) bez_beleski=1 ;;
    *) sed -n '2,12p' "$0"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { sed -n '2,12p' "$0"; exit 1; }

# U Dockeru kontejner vidi samo /snimci i /modeli. Sve van /snimci nestane sa --rm.
if [ -f /.dockerenv ] && [ -n "$izlaz" ]; then
  case "$izlaz" in
    /snimci|/snimci/*|[!/]*) ;;
    *) greska "u Dockeru -o mora biti unutar /snimci (npr. -o beleske), inace beleske nestanu sa kontejnerom" ;;
  esac
fi

for snimak in "$@"; do
  [ -f "$snimak" ] || greska "nema fajla: $snimak"
done

# Claude: u Dockeru i na Linuxu "claude", iz WSL-a Windows claude preko cmd.exe
if [ -n "${CLAUDE_CMD:-}" ]; then read -ra CLAUDE <<< "$CLAUDE_CMD"
elif command -v claude >/dev/null && claude --version >/dev/null 2>&1; then CLAUDE=(claude)
elif command -v cmd.exe >/dev/null; then CLAUDE=(cmd.exe /c claude)
else CLAUDE=(); fi
# token iz .env mora eksplicitno da predje iz WSL-a u Windows proces
# (i "claude" iz WSL-a je cesto Windows claude preko npm shim-a)
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  export WSLENV="CLAUDE_CODE_OAUTH_TOKEN${WSLENV:+:$WSLENV}"
fi

txt_za() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "${1%.*}").txt"; }

# 0. Modeli: pri prvom pokretanju se sami skinu, posle se samo proveri da su tu
treba_whisper=0
for snimak in "$@"; do
  [ $preskoci -eq 1 ] && [ -s "$(txt_za "$snimak")" ] || treba_whisper=1
done
if [ $treba_whisper -eq 1 ]; then
  python="$(dirname "$(command -v "$WHISPERX" || echo .)")/python"
  [ -x "$python" ] || python=python3
  "$python" "$ROOT/alati/skini-modele.py" --tiho --model "$MODEL" \
    || greska "modeli nisu spremni, pogledaj poruku iznad"
fi

# 1. Transkripcija (HF_TOKEN WhisperX sam cita iz okruzenja)
transkripti=()
for snimak in "$@"; do
  txt="$(txt_za "$snimak")"
  dir="$(dirname "$txt")"
  if [ $preskoci -eq 1 ] && [ -s "$txt" ]; then
    log "preskacem transkripciju, vec postoji: $(basename "$txt")"
  else
    log "transkribujem $(basename "$snimak") ..."
    start=$(date +%s)
    pocetak="$(mktemp)"  # da se vidi da je .txt napravljen sada, a ne ostao od ranije
    "$WHISPERX" "$snimak" \
      --model "$MODEL" --language "$JEZIK" --device cuda --compute_type float16 \
      --no_align \
      --diarize --min_speakers 2 --max_speakers 6 \
      --output_format txt --output_dir "$dir" 2> "$dir/.whisperx.log" \
      || greska "WhisperX nije uspeo, pogledaj $dir/.whisperx.log"
    # WhisperX ume da zavrsi "uspesno" a da ne napravi fajl (npr. kad fale CUDA biblioteke)
    [ -s "$txt" ] && [ "$txt" -nt "$pocetak" ] \
      || greska "WhisperX nije napravio $(basename "$txt"), pogledaj $dir/.whisperx.log"
    rm -f "$pocetak"
    log "gotovo za $(( $(date +%s) - start ))s: $(basename "$txt")"
  fi
  transkripti+=("$txt")
done

[ $bez_beleski -eq 1 ] && { log "samo transkript, kraj."; exit 0; }
[ ${#CLAUDE[@]} -gt 0 ] || greska "nema Claude CLI, beleske preskocene"

# 2. Beleske preko Claude
ime="${ime:-$(basename "${1%.*}")}"
izlaz="${izlaz:-$(dirname "${transkripti[0]}")}"
mkdir -p "$izlaz"
beleske="$izlaz/$ime.md"
ocena="$izlaz/$ime.ocena.md"
rm -f "$ocena"  # da se nova statistika ne doda na staru ocenu

log "Claude ($CLAUDE_MODEL) pise beleske i ocenu transkripta ..."
claude_start=$(date +%s)
# Bez alata, bez MCP servera i sa kratkim sistemskim promptom: Claude samo cita i pise tekst.
# "|| true": i kad Claude vrati gresku, JSON ispod kaze sta je bilo.
{
  cat "$ROOT/prompts/beleske.md"; echo
  cat "$ROOT/prompts/stil.md"; echo
  cat "$ROOT/prompts/ocena.md"; echo
  i=1
  for t in "${transkripti[@]}"; do
    echo "## Transkript, deo $i ($(basename "$t"))"; echo
    cat "$t"; echo
    i=$((i + 1))
  done
} | "${CLAUDE[@]}" -p --model "$CLAUDE_MODEL" --output-format json \
    --tools "" --strict-mcp-config --no-session-persistence \
    --system-prompt "Od transkripta snimka govora pravis beleske na srpskom. Ne koristis alate, samo pises tekst." \
  | tr -d '\r' > "$beleske.json" || true
claude_s=$(( $(date +%s) - claude_start ))

# JSON odgovor: tekst ide dalje, potrosnja tokena ide u statistiku
python3 - "$beleske.json" "$beleske.tmp" > "$beleske.usage" <<'PY' \
  || greska "Claude nije napravio beleske (sirov odgovor: $beleske.json)"
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    sys.exit("Claude nije vratio JSON. Da li je Claude CLI instaliran i token ispravan?")
if d.get("is_error"):
    sys.exit(f"Claude javlja gresku: {d.get('result') or d.get('subtype')}")
open(sys.argv[2], "w", encoding="utf-8").write(d.get("result", ""))
u = d.get("usage", {})
ulaz = sum(u.get(k, 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
misli = (u.get("output_tokens_details") or {}).get("thinking_tokens")
modeli = ", ".join(d.get("modelUsage", {})) or "?"
print(f"- Model: {modeli}")
print(f"- Ulazni tokeni: {ulaz} (od toga iz keša: {u.get('cache_read_input_tokens', 0)})")
print(f"- Izlazni tokeni: {u.get('output_tokens', 0)}"
      + (f" (od toga razmišljanje: {misli})" if misli is not None else ""))
print(f"- Cena po API cenovniku: {d.get('total_cost_usd', 0):.2f} USD (samo za poređenje, na Pro/Max planu ide iz limita)")
PY
rm -f "$beleske.json"

[ -s "$beleske.tmp" ] || { rm -f "$beleske.tmp"; greska "Claude nije vratio nista"; }

# 3. Garancija stila: bez em/en crta i bez ``` omotaca
sed -E -e 's/ ?— ?/, /g' -e 's/([0-9]) ?– ?([0-9])/\1-\2/g' -e 's/ ?– ?/, /g' \
       -e '1{/^```/d}' -e '${/^```$/d}' "$beleske.tmp" > "$beleske.sed"
rm -f "$beleske.tmp"

# 4. Ocena transkripta ide u poseban fajl (sve posle reda ===OCENA===)
oznaka='^[[:space:]*]*===OCENA===[[:space:]*]*$'
if grep -qE "$oznaka" "$beleske.sed"; then
  sed -E "/$oznaka/,\$d" "$beleske.sed" > "$beleske"
  sed -E "1,/$oznaka/d" "$beleske.sed" > "$ocena"
  rm -f "$beleske.sed"
  log "ocena: $ocena ($(grep -m1 -i 'razumljivost' "$ocena" || echo 'bez ocene'))"
else
  mv "$beleske.sed" "$beleske"
  printf '# Ocena transkripta\n\nClaude ovaj put nije napisao ocenu.\n' > "$ocena"
  log "Claude nije napisao ocenu transkripta, u $ocena je samo statistika"
fi

# 5. Statistika: koliko zvuka, koliko teksta, koliko tokena
audio_s=0
if command -v ffprobe >/dev/null; then
  for s in "$@"; do
    d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$s" 2>/dev/null || echo 0)
    audio_s=$(awk -v a="$audio_s" -v b="${d:-0}" 'BEGIN { printf "%d", a + b }')
  done
fi
{
  echo; echo "## Statistika"; echo
  echo "- Snimak: $(( audio_s / 60 )) min $(( audio_s % 60 )) s (delova: $#)"
  echo "- Transkript: $(cat "${transkripti[@]}" | wc -w) reči, $(cat "${transkripti[@]}" | wc -m) znakova"
  echo "- Beleške: $(wc -w < "$beleske") reči"
  echo "- Claude korak: $(( claude_s / 60 )) min $(( claude_s % 60 )) s"
  cat "$beleske.usage"
} >> "$ocena"
rm -f "$beleske.usage"
log "statistika: $(grep -m1 'Ulazni' "$ocena" || true)"

log "beleske: $beleske ($(wc -w < "$beleske") reci)"
