# voice-ptt (macOS PTT prototype)

**Phase 7 P0** — прожить UX голосового PTT до траты денег на железо.

Global hotkey → mic capture → `POST /v1/voice/audio` → transcript
notification + spoken reply через `say`.

## Config

Скопируй `config.example.json` → `~/.voice-ptt/config.json`, впиши
`backendToken` из VDS `~/.voice-service/secrets.env`.

```jsonc
{
    "backendURL": "https://cashflow-game.ru",
    "backendToken": "…",
    "clientId": "mac-ptt-dev",
    "hotkeyCode": 80,    // F19 = 80, F13 = 105
    "speakReply": true,
    "sayVoice": "Yuri"   // ru: Yuri/Milena; en: Samantha
}
```

## Build & run (на mac-home)

```bash
cd ~/projects/voice/clients/macos-ptt   # или где смонтирован repo
swift build -c release
.build/release/VoicePTT
```

Первый запуск попросит:

1. **Microphone** — TCC prompt автоматически
2. **Accessibility** — нужно вручную:
   `System Settings > Privacy & Security > Accessibility` → добавить
   бинарник `VoicePTT` (или Terminal если запускаешь оттуда) и включить

После грант — рестарт бинарника.

## Hotkey (F19 default)

**F19 keycode = 80.** На современных Apple-клавиатурах прямой F19 нет.
Варианты:

- **Karabiner-Elements** (рекомендую): remap `Right Command` → `F19` или
  `Caps Lock` → `F19`. См. `~/.config/karabiner/karabiner.json`
- **Fn+Escape** — на некоторых MBP выдаёт F19 нативно
- Изменить `hotkeyCode` в config на что-то доступное (F13 = 105 бывает
  на full-size клавиатурах)

## UX loop

- **Hold key** — 🔴 recording (16 kHz mono PCM WAV)
- **Release** — ⏳ uploading → transcript в notification + `say <text>`
- **Release < 0.3s** — ❓ ignore (accidental tap)

## Что мерить неделю

- Насколько удобно нажимать F19 в разных положениях руки
- Задержка p50 (пиши в notes: <2с ok, 2-4с граница, >4с бесит)
- Ложные срабатывания (accidental hold)
- Ошибки транскрипции (сравнить с тем что говорил)
- Комфортно ли ждать `say` или хочется другой feedback

Если UX норм → идём в железо (Phase 7 P1-P5).
Если бесит → закрываем Phase 7, ищем другой путь.

## Refs

- Backend endpoint spec: `voice-repo/specs/backend-protocol.md#endpoint--voice-audio-in`
- Phase 7 plan: `voice-repo/docs/mcu-client.md`
- Tasks: `voice-repo/.claude/TASKS.md#phase-7`
