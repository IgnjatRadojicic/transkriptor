# Transkriptor

Snimak govora u transkript i beleške, jednom komandom.

Duže izlaganje snimim telefonom. Transkriptor ga lokalno na grafičkoj pretvori u tekst sa oznakama ko govori. Zatim Claude od teksta napravi beleške na srpskom i oceni koliko je snimak bio razumljiv. Zvuk nikad ne napušta računar. Claude dobija samo tekst i troši limit Pro ili Max plana, bez posebne naplate.

```
docker compose run --rm transkriptor -n Sesija03 sesija3-1.m4a sesija3-2.m4a
```

Rezultat su tri fajla pored snimka: transkript, beleške sa pitanjima za ponavljanje i ocena transkripta sa statistikom.

## Sadržaj

- [Zašto](#zašto)
- [Kako radi](#kako-radi)
- [Rezultati](#rezultati)
- [Šta treba](#šta-treba)
- [Instalacija na novom računaru](#instalacija-na-novom-računaru)
- [Upotreba](#upotreba)
- [Podešavanja](#podešavanja)
- [Šta je gde](#šta-je-gde)
- [Problemi i rešenja](#problemi-i-rešenja)
- [Ograničenja](#ograničenja)
- [Licenca](#licenca)

## Zašto

Hteo sam beleške sa svakog dužeg snimka bez trošenja pola Claude limita. Slanje zvuka je skupo i Claude Code ga ionako ne prima. Zato zvuk pretvaram u tekst na svom računaru preko Whisper modela, a Claude dobija samo tekst. Dva sata govora je oko 11 000 reči, otprilike kao jedan veći fajl koda.

## Kako radi

```
snimak.m4a
   |
   |  WhisperX (lokalno, GPU, bez interneta)
   |    1. VAD: nađe delove gde se priča, tišinu preskoči
   |    2. Whisper large-v3-turbo: govor u tekst, jezik sr
   |    3. pyannote: ko govori
   v
snimak.txt        [SPEAKER_01]: Koja je razlika između procesa i niti? ...
   |
   |  claude -p (Pro/Max plan, bez alata i MCP servera)
   |    dobija prompts/beleske.md + stil.md + ocena.md + sve transkripte
   |    ispravlja termine iz konteksta, izbacuje halucinacije,
   |    spaja delove, piše beleške pa ocenu transkripta
   |
   |  sed: zamena em/en crta ako ih je Claude ipak ubacio
   |  podela odgovora na red ===OCENA===
   v
snimak.md         beleške + pitanja za ponavljanje
snimak.ocena.md   ocena transkripta + statistika
```

Svi delovi jednog snimka (npr. pre i posle pauze) se daju zajedno i dobija se jedan fajl sa beleškama. Claude se poziva jednom za ceo snimak.

### Docker

Image sadrži sve što pipeline treba: Python, WhisperX sa PyTorch-om i CUDA bibliotekama, ffmpeg i Claude CLI. Pravi se jednom sa `docker compose build`.

Svaka `docker compose run` komanda napravi jedan kontejner iz tog image-a. Kontejner pokrene `transkriptor.sh`, obradi sve delove snimka i obriše se (`--rm`). Snimci i modeli nisu u image-u. Oni su u tvojim folderima koji se prikače u kontejner kao `/snimci` i `/modeli`, pa preživljavaju svaki rebuild.

Skripta i promptovi se kopiraju u image pri build-u. Posle izmene u `transkriptor.sh` ili `prompts/` treba ponovo `docker compose build` (oko 40 s, ostalo ide iz keša).

### Claude bez alata

Običan `claude -p` uz svaki poziv šalje ceo Claude Code: dugačak sistemski prompt, opise svih alata i MCP servere. Za beleške to ne treba jer Claude samo čita i piše tekst. Zato skripta poziva:

```
claude -p --tools "" --strict-mcp-config --system-prompt "..." --output-format json
```

| Poziv (na pitanju "Odgovori samo: OK") | Ulazni tokeni |
|---|---:|
| `claude -p` | 45 333 |
| `claude -p --tools "" --strict-mcp-config --system-prompt "..."` | 736 |

Usput je i bezbednije. Šta god da piše u transkriptu, Claude nema alat kojim bi nešto pokrenuo.

`--bare` bi bio još kraći ali ne čita OAuth token, pa ne radi sa Pro/Max planom.

### Ocena transkripta

Posle beleški Claude oceni koliko mu je bilo lako da razume transkript: razumljivost, kontekst i pouzdanost beleški od 1 do 10, procenat teksta koji je bio jasan, lista nejasnih mesta i tabela termina koje je ispravio. Ocena ide u poseban fajl i ne ulazi u beleške. Kad ocena padne, vreme je da se snima bliže.

## Rezultati

Mereno na jednom snimku u dva dela, 59 i 50 minuta. Laptop sa RTX 3050 (4 GB).

**Snimak je namerno težak slučaj.** Telefon je bio oko 15 m od govornika i kvalitet zvuka je loš. U daljem tekstu glavni govornik je "daleki speaker", a ostali su "pitači", jer se uglavnom javljaju sa pitanjima. Daleki speaker se čuje ali ne jasno, a pitači se često ne čuju. Svi rezultati ispod su za takav snimak. Sa telefonom bliže govorniku treba očekivati bolje brojke.

Svi primeri teksta ispod (termini, fraze, rečenice) su izmišljeni po uzoru na prave greške, da README ne prenosi sadržaj snimka. Brojke su izmerene.

### Brzina

| Korak | Vreme |
|---|---:|
| WhisperX za 50 min snimka, samo tekst | oko 80 s |
| WhisperX za 50 min snimka, tekst + govornici | 5 min 6 s |
| Ceo pipeline u Dockeru za 50 min snimka | 6 min 4 s |
| Claude korak za 50 min snimka (claude-sonnet-5-5) | 40 s |

### Potrošnja Claude-a

| | Oba dela, claude-sonnet-5 | Drugi deo, claude-sonnet-5-5 |
|---|---:|---:|
| Snimak | 109 min | 50 min |
| Transkript | 11 220 reči | 4700 reči |
| Ulazni tokeni | 41 776 | 15 823 |
| Izlazni tokeni | 24 649 | 4502 |
| Od toga razmišljanje | nije mereno | 0 |
| Vreme | 6 min 21 s | 40 s |
| Cena po API cenovniku | 0,41 USD | 0,11 USD |

Cena po API cenovniku je samo za poređenje. Na Pro/Max planu se ništa ne plaća posebno, poziv ide iz petočasovnog limita. Snimak od dva sata je potrošio oko 2% limita na Pro planu.

`sonnet` je alias i zavisi od verzije Claude CLI-ja. Sa CLI 2.1.278 to je bio claude-sonnet-5, sa 2.1.300 claude-sonnet-5-5. Noviji model nije razmišljao pre pisanja, pa je bio oko četiri puta brži po reči transkripta.

### Ocena transkripta

Claude je u četiri nezavisna pokretanja, sa dva različita modela, dao skoro istu ocenu:

| | Ocena |
|---|---:|
| Razumljivost (tekst sam po sebi) | 4/10 svaki put |
| Kontekst (može li se zaključiti iz okoline) | 6 do 7/10 |
| Pouzdanost beleški | 6/10 svaki put |
| Razumljivo odmah | 30 do 35% |
| Razumljivo tek iz konteksta | 40 do 50% |
| Nerazumljivo | 20 do 25% |

Za snimak sa 15 m to znači da se iz transkripta može izvući većina sadržaja, ali skoro polovina tek iz konteksta. Beleške su upotrebljive. Brojke, imena i anegdote treba proveriti sa drugim izvorom ako postoji.

Ovakve greške Whisper pravi sa stručnim terminima, a Claude ih ispravlja (primeri su ilustrativni):

| Termin | Kako ga Whisper čuje |
|---|---|
| Python | Pajton, Pejton, Bajton |
| Docker | Doker, Dokr, Toker |
| SQL | sikvel, es ku el |
| API | ej pi aj, epiaj |
| GitHub | Git hab, Gidhab |
| Linux | Lajnuks, Linuks |
| TCP/IP | ti si pi aj pi, tecepe |
| Dijkstrin algoritam | Dajkstrin, Dikstrov algoritam |

Whisper dobro hvata običan srpski govor ali stručne termine na engleskom skoro uvek promaši. Zato je Claude korak bitan. On iz konteksta zna da je "Pajton" u priči o skriptama zapravo Python.

### Halucinacije

Običan Whisper u tišini ili šumu ume da izmisli rečenicu i ponavlja je u krug. WhisperX to rešava jer prvo izbaci tišinu. Na prvom delu snimka:

| Ponavljanje | Whisper | WhisperX |
|---|---:|---:|
| "Hvala što ste gledali." | 22 | 0 |
| "Pretplatite se na kanal." | 15 | 0 |
| "Vidimo se sledeći put." | 11 | 0 |
| "I tako dalje." | 8 | 0 |

Fraze su zamenjene tipičnim Whisper halucinacijama, a broj ponavljanja je izmeren. Ostane par ponavljanja na mestima gde je bio šum (npr. "Hvala na pažnji."). Claude ih izbaci.

### Govornici

Daleki speaker dobija jednu oznaku za skoro sve linije. Pitači se ne razlikuju pouzdano. Whisper pravi segmente do 30 s i oznaka govornika ide na ceo segment, pa se pitanje često spoji sa odgovorom dalekog speakera. Na drugom delu snimka je bilo 113 linija dalekog speakera i 3 linije pitača. Za beleške to nije veliki problem jer Claude iz konteksta vidi ko pita a ko odgovara.

Ranije sam koristio hrvatski wav2vec2 model za poravnanje reči. Oznake su bile finije ali je model pravio probleme pa sam ga izbacio. Postoji i srpski model, [classla/wav2vec2-xls-r-juznevesti-sr](https://huggingface.co/classla/wav2vec2-xls-r-juznevesti-sr). Nisam ga još probao.

## Šta treba

| | |
|---|---|
| Grafička | NVIDIA sa bar 4 GB memorije |
| Sistem | Windows 10/11 sa WSL2, ili Linux |
| Claude | Pro ili Max nalog i Claude Code (samo za dobijanje tokena) |
| Hugging Face | besplatan nalog, zbog modela za govornike |
| Prostor (Docker) | oko 15 GB za image i 2 GB za modele |
| Prostor (WSL) | oko 8 GB za Python pakete i 2 GB za modele |
| Internet | za instalaciju i prvo pokretanje, posle samo za Claude korak |

## Instalacija na novom računaru

Ceo put od praznog računara do prvih beleški. Prvi put traje oko pola sata, najviše zbog skidanja.

### 1. Programi

1. **NVIDIA drajver.** Najnoviji sa nvidia.com. CUDA ne treba posebno, dolazi u Docker image-u.
2. **WSL2.** U PowerShell-u kao administrator: `wsl --install`, pa restart.
3. **Docker Desktop** sa docker.com. U Settings proveri da je uključen "Use the WSL 2 based engine". Ako je C: mali, u Settings, Resources premesti disk image na drugi disk pre prvog build-a.
4. **Git**, da bi skinuo repo.
5. **Claude Code**, uputstvo je na [claude.com/claude-code](https://claude.com/claude-code). Treba samo za `claude setup-token`, sam pipeline koristi Claude iz Docker-a.

### 2. Tokeni

**Hugging Face**, za model koji prepoznaje ko govori:

1. Napravi nalog na huggingface.co.
2. Otvori [pyannote/speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1) i prihvati uslove. Bez ovoga model neće hteti da se skine ni sa tokenom.
3. Settings, Access Tokens, New token, tip "Read". Kopiraj ga.

**Claude**, za beleške:

```
claude setup-token
```

Otvori se browser, uloguješ se i dobiješ token koji počinje sa `sk-ant-oat`. Token troši limit plana i ništa se ne naplaćuje posebno.

Pazi da u okruženju nemaš `ANTHROPIC_API_KEY`. Ako postoji, Claude Code koristi njega umesto plana i to se naplaćuje.

### 3. Repo i `.env`

```
git clone https://github.com/IgnjatRadojicic/transkriptor.git
cd transkriptor
cp .env.example .env
```

U `.env` upiši `HF_TOKEN` i `CLAUDE_CODE_OAUTH_TOKEN`. Ostalo može da ostane kako jeste. `.env` je u `.gitignore` i ne ulazi u Docker image. Ne šalji ga nikome.

### 4. Build

```
docker compose build
```

Prvi build traje 10 do 20 minuta i skida nekoliko GB, najviše PyTorch sa CUDA bibliotekama. Ako stane na pola, pokreni ponovo i nastaviće od poslednjeg završenog koraka. Gotov image je 14,8 GB.

Provera da kontejner vidi grafičku:

```
docker compose run --rm --entrypoint nvidia-smi transkriptor
```

Treba da ispiše ime grafičke. Ako javi grešku, Docker ne prosleđuje GPU. Proveri drajver i WSL2 engine u Docker Desktop podešavanjima.

### 5. Prvo pokretanje

Snimak stavi u folder `snimci` unutar `transkriptor` foldera, pa:

```
docker compose run --rm transkriptor sesija1.m4a
```

Prvi put skripta vidi da modeli fale i skine ih sama (oko 1,6 GB). Posle toga ide transkripcija, pa Claude. Na kraju su u `snimci` folderu:

| Fajl | Šta je |
|---|---|
| `sesija1.txt` | sirov transkript sa oznakama govornika |
| `sesija1.md` | beleške i pitanja za ponavljanje |
| `sesija1.ocena.md` | ocena transkripta, nejasna mesta, ispravljeni termini, statistika |

Svako sledeće pokretanje preskače skidanje i kreće odmah.

### Bez Dockera (WSL)

Isti pipeline može da radi direktno u WSL-u (Debian ili Ubuntu):

```
./alati/instaliraj-wsl.sh
transkriptor snimak.m4a
```

Skripta instalira ffmpeg i WhisperX u `~/whisperx-env` i napravi komandu `transkriptor` u `~/.local/bin`. Ako komanda nije nađena, otvori novi terminal.

Claude CLI ova skripta ne instalira. Treba ti ili u WSL-u ili na Windowsu. Ako je na Windowsu, `transkriptor` ga sam nađe i prosledi mu token preko `WSLENV`. Modeli idu u `~/.cache/huggingface`, drugi folder se zadaje sa `HF_HOME` u `.env`.

## Upotreba

```
transkriptor [opcije] deo1.m4a [deo2.m4a ...]

  -n IME     ime fajla sa beleškama (default: ime prvog snimka)
  -o FOLDER  gde idu beleške (default: pored snimka)
  -t         preskoči transkripciju ako .txt već postoji
  -b         samo transkript, bez beleški
```

U Dockeru se ispred piše `docker compose run --rm transkriptor`, a komanda se pokreće iz `transkriptor` foldera.

```
# snimak u dva dela
docker compose run --rm transkriptor -n Sesija03 sesija3-1.m4a sesija3-2.m4a

# promenio sam prompt i hoću nove beleške bez ponovne transkripcije
docker compose run --rm transkriptor -t -n Sesija03 sesija3-1.m4a sesija3-2.m4a

# jednom sa Opus modelom
docker compose run --rm -e CLAUDE_MODEL=opus transkriptor -t -n Sesija03 sesija3-1.m4a sesija3-2.m4a
```

U Dockeru kontejner vidi samo `snimci` folder. Zato `-o` mora biti relativna putanja (`-o beleske` znači `snimci/beleske`). Apsolutnu putanju van `/snimci` skripta odbije, jer bi beleške nestale zajedno sa kontejnerom.

## Podešavanja

Sve ide u `.env`:

| Promenljiva | Default | Šta radi |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | | token iz `claude setup-token` |
| `HF_TOKEN` | | Hugging Face token, treba samo za prvo skidanje |
| `CLAUDE_MODEL` | `sonnet` | model za beleške, `opus` je bolji ali troši više |
| `MODEL` | `large-v3-turbo` | Whisper model |
| `JEZIK` | `sr` | jezik snimka |
| `HF_HUB_OFFLINE` | `1` | WhisperX bez interneta, modeli koji fale se ipak skinu |
| `SNIMCI` | `./snimci` | Docker: folder sa snimcima |
| `MODELI` | `./modeli` | Docker: folder sa modelima |
| `HF_HOME` | `~/.cache/huggingface` | WSL: folder sa modelima, Docker ga ignoriše |
| `CLAUDE_CMD` | sam nađe | ručno zadata komanda za Claude CLI |

Promenljiva postavljena spolja ima prednost nad `.env`: u WSL-u `CLAUDE_MODEL=opus transkriptor ...`, u Dockeru `-e CLAUDE_MODEL=opus`. `.env` se čita kao obične `KEY=vrednost` linije, isto kao Docker `env_file`. Navodnici i komentari posle ` #` rade, a Windows završeci redova ne smetaju.

Šta Claude piše menja se u promptovima:

| Fajl | Šta određuje |
|---|---|
| `prompts/beleske.md` | šta beleške sadrže |
| `prompts/stil.md` | kako su napisane: latinica, bez em crta, kratke direktne rečenice |
| `prompts/ocena.md` | šta se ocenjuje u transkriptu |

Claude CLI u image-u je zaključan na verziju iz `Dockerfile`-a (`CLAUDE_VERSION`), da novi build ne promeni ponašanje. Novija verzija: `docker compose build --build-arg CLAUDE_VERSION=<verzija>`.

### Modeli ručno

Modeli se skidaju sami. Ako hoćeš unapred, ili da proveriš da su tu:

```
docker compose run --rm --entrypoint python transkriptor /app/alati/skini-modele.py
```

| Model | Veličina | Zašto |
|---|---:|---|
| `mobiuslabsgmbh/faster-whisper-large-v3-turbo` | 1,6 GB | govor u tekst |
| `pyannote/speaker-diarization-community-1` | 32 MB | ko govori |
| pyannote VAD | mali | dolazi uz whisperx paket, ne skida se |

## Šta je gde

```
transkriptor.sh          ceo pipeline
prompts/beleske.md       uputstvo za beleške
prompts/stil.md          stil pisanja
prompts/ocena.md         uputstvo za ocenu transkripta
alati/skini-modele.py    provera i skidanje modela (pipeline je sam poziva)
alati/instaliraj-wsl.sh  instalacija bez Dockera
Dockerfile               od čega se pravi image
docker-compose.yml       kako se pokreće kontejner (folderi, GPU, .env)
.env.example             primer podešavanja
```

| Gde | Šta | Ostaje posle pokretanja |
|---|---|---|
| `snimci/` | snimci, transkripti, beleške, ocene | da |
| `modeli/` | Whisper i pyannote modeli | da |
| Docker image | ceo instaliran sistem, 14,8 GB | da, dok ga ne obrišeš |
| kontejner | privremena kopija za jedno pokretanje | ne, briše se sam |

## Problemi i rešenja

Ovo je sve izašlo pri postavljanju i možda nekome uštedi vreme.

- **Docker Desktop neće da se pokrene.** Greška `remove ...\Docker\run\dockerInference: The file cannot be accessed by the system`. To je zaostao Unix socket. Ugasi Docker, obriši ga iz WSL-a sa `rm /mnt/c/Users/<ime>/AppData/Local/Docker/run/dockerInference` i pokreni ponovo.
- **C: disk se napunio.** WSL i Docker Desktop po defaultu drže diskove na C:. WSL se premešta sa `wsl --manage Debian --move D:\WSL\Debian`, Docker u Settings, Resources.
- **WhisperX javi grešku `LocalEntryNotFoundError`.** `MODELI` pokazuje na prazan folder a internet je isključen. Proveri putanju u `.env`.
- **Whisper završi a nema `.txt`.** Fale `libcublas` i `cudnn`. U Dockeru dolaze sa PyTorch-om, u WSL-u ih WhisperX povuče sam. Skripta ovo sada prijavi umesto da nastavi.
- **"No space left on device" a disk je prazan.** Na Debianu 13 `/tmp` je u RAM-u (oko 4 GB) i PyTorch se ne raspakuje. `instaliraj-wsl.sh` zato koristi `TMPDIR=~/pip-tmp`.
- **Skidanje iz WSL-a staje na pola.** Veliki fajlovi su se zaglavljivali bez greške. Pomaže ponovno pokretanje, `skini-modele.py` sam pokuša do 5 puta.
- **`--initial_prompt` sa listom termina pravi štetu.** Trebalo je da pomogne sa terminima a tekst prompta se pojavio 24 puta u transkriptu. Bolje je da termine ispravi Claude.
- **WhisperX nema alignment model za srpski.** Hrvatski `classla/wav2vec2-xls-r-parlaspeech-hr` je radio ali je pravio probleme, pa sada ide `--no_align`.
- **Claude iz WSL-a ne vidi token.** `claude` u WSL-u je često Windows program preko npm prečice. Promenljive iz WSL-a ne prelaze u Windows proces osim ako su u `WSLENV`, i skripta to radi sama.
- **Claude greška.** Skripta ispiše šta je Claude javio, npr. `401 Invalid bearer token` znači da je `CLAUDE_CODE_OAUTH_TOKEN` pogrešan ili istekao.
- **Task Manager pokazuje 0% na grafičkoj.** Prikazuje 3D a ne CUDA. U grafiku promeni na "Cuda" ili proveri sa `nvidia-smi`.

## Ograničenja

- Ocena transkripta je Claude-ova procena, ne merenje. Za pravi WER treba ručno ispraviti deo transkripta.
- Prepoznavanje govornika je pouzdano samo za glavnog, dalekog speakera.
- Kvalitet zavisi od snimka. Sa 15 m je četvrtina teksta nerazumljiva, a pitači se često ne čuju.
- Pyannote model traži Hugging Face nalog za prvo skidanje.
- Claude korak treba internet i troši limit plana.
- Testirano samo na Windowsu 11 sa WSL2 i RTX 3050.

## Licenca

Kod je pod [MIT licencom](LICENSE). Slobodno ga koristi, menjaj i deli, uz zadržavanje obaveštenja o autoru.

Modeli nisu deo repoa i imaju svoje licence. Whisper i WhisperX su otvoreni, a pyannote model traži da na Hugging Face-u sam prihvatiš njegove uslove.
