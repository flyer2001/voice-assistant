# voice-agent-mac (Path A)

Hands-free voice assistant для macOS. Porcupine wake word активирует OpenAI
Realtime API, диалог идёт стримом. ~500 ms до первого звука ответа.

Aimed at: сессии где руки заняты (racing wheel, готовка, ходьба),
непрерывный голосовой диалог без PTT.

## Setup (mac-work)

### 1. Python venv

```bash
cd voice-repo/clients/voice-agent-mac
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Porcupine access key (free tier)

- Регистрация: https://console.picovoice.ai
- Дашборд → скопируй Access Key

### 3. Custom wake word «Алёнка»

- Console → **Porcupine → Custom Wake Words** → **+ Add**
- Language: **Russian**
- Phrase: `Алёнка`
- Platform: **macOS** (arm64 если Apple Silicon, иначе x86_64)
- Wait ~2 min → download `.ppn` файл
- Положи куда угодно, например `~/voice-agent-mac/alyonka_mac.ppn`

Free tier: 3 custom keywords/month, unlimited runtime.

### 4. Config

```bash
mkdir -p ~/.voice-agent-mac
cp config.example.json ~/.voice-agent-mac/config.json
# Впиши: openai_api_key, porcupine_access_key, porcupine_keyword_path
```

### 5. Run

```bash
source .venv/bin/activate
python agent.py
```

macOS попросит доступ к микрофону — grant.

## UX

- Скажи **«Алёнка»** → `[Wake] detected!` → говори свободно
- Server VAD определит когда закончил (700 ms тишины) → стриминг ответа
- 8 секунд без активности → возврат к wake mode
- Ctrl-C для выхода

## Cost

- **Realtime API:** ~$0.06/min input audio + $0.24/min output audio
  → ~$0.20-0.50 за час разговора при активном использовании
- **Porcupine:** free tier, 3 custom keywords/month

## Голоса Realtime API (без fable!)

`alloy`, `ash`, `ballad`, `coral`, `echo`, `sage`, `shimmer`, `verse`.
Fable недоступен в Realtime API — только в standalone TTS API. Смени
`voice` в config если verse не нравится.

## Что дальше

**Path B** (вечер, если Path A прижился):
Chain — local mic → local WhisperKit → Claude Sonnet 4.6 → OpenAI TTS
`fable` stream → speaker. Fable голос, но 2-3 s latency.

**Wake word tuning:**
- Если ложные срабатывания в игре → пересобери keyword с более
  специфичным словом ("Алёнушка", "Алёна привет")
- Если не срабатывает → скажи громче/чётче или уменьши threshold в
  Porcupine (`sensitivities` param — TODO)

**Real conversation memory** — Realtime API держит контекст в рамках
одной сессии. После 8 s quiet — новая сессия, память сбрасывается. Если
надо persist — храни transcripts в файле, injectим в новый session.instructions.

## Skipped

- Beep-cue при wake detection (можно добавить `NSBeep()` или playback короткого WAV)
- Level meter / mic gain adjustment
- Log в JSONL (как в macos-ptt) — add если понадобится анализ
- Multi-turn memory across wake cycles — Realtime session drop сбрасывает

Add эти когда почувствуешь боль в реальном использовании.
