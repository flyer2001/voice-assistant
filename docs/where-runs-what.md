# Где что крутится

Карта прода на 2026-09-02. Заведена потому, что путались оба: в `VISION.md`
описан план (WhisperKit на iPhone), а не то, что реально работает.

## Два входа, два разных Whisper

```
ТЫ ДИКТУЕШЬ В VK (телефон, откуда угодно)
  VK Long Poll
    └─► VDS: voice-backend (Hummingbird, :8089)
          ├─► ubuntu-home 192.168.88.13:8000
          │     faster-whisper-large-v3-turbo, CUDA fp16     ← STT здесь
          └─► Happy inject в Claude-сессию
                └─► ответ: voice-reply-both (текст + Yandex TTS) обратно в VK

ТЫ ГОВОРИШЬ В МИКРОФОН МАКА
  mac-home: ~/bin/voice-agent-t3
    └─► mlx-whisper large-v3, Metal, локально         ← STT здесь, другой
          └─► HTTPS на VDS /v1/voice/intent
                └─► Happy inject в Claude-сессию
                      └─► Stop hook → voice-mac-reply-both → afplay в колонки
```

**VDS распознаванием не занимается.** У него нет видеокарты: только приём,
маршрутизация по фокусу, инжект и синтез речи.

## Кто за что отвечает

| машина | роль | что сломается, если недоступна |
|---|---|---|
| **VDS** | backend, роутинг, аудит, TTS, врапперы | всё |
| **ubuntu-home** (192.168.88.13) | Whisper для **VK-пути**, CUDA | голосовые из VK не распознаются, аудио копится в `raw/` |
| **mac-home** | Whisper для **своего микрофона**, Metal | не работает голосовой агент на маке; на VK не влияет |
| **Yandex SpeechKit** (облако) | синтез речи | ответы приходят только текстом |

Machines: ubuntu-home и mac-home независимы. Падение одного не трогает
второй путь — 2026-09-02 ubuntu-home спал, а мак спокойно распознал
сохранённое аудио вручную.

## Грабли ubuntu-home

Это **dual-boot** с Windows на одном ноутбуке MSI GP66. Whisper стоит только
в Linux. После пробуждения по WoL машина может подняться в Windows — тогда
VK-путь молчит, хотя хост пингуется.

Как опознать: ssh отлупит по ключу (`Permission denied (publickey)`) —
host keys у Windows и Ubuntu разные. Проверка и лечение:

```bash
curl -s http://192.168.88.13:8000/health          # молчит → не Linux или сервис лёг
/root/projects/agentops/bin/wake-lan.sh ubuntu-home   # разбудить
ssh win-home 'shutdown /r /t 5'                   # из Windows в Linux через GRUB
ssh-keygen -R 192.168.88.13                       # обязательно после смены ОС
```

Полная процедура и MAC-адреса — `~/.claude/docs/home-machines.md`.

## Восстановить потерянное сообщение

Аудио не теряется никогда, лежит в `/var/lib/voice-bot/raw/`. Найти по номеру
из уведомления и прогнать вручную:

```bash
grep '"msg_id":1108' /var/lib/voice-bot/audit.jsonl      # найти запись и путь
scp <путь>.ogg mac-home:~/voice-corpus/lost.ogg
ssh mac-home '~/.venvs/voice-agent/bin/python -c "
import mlx_whisper
print(mlx_whisper.transcribe(\"/Users/flyer2001/voice-corpus/lost.ogg\",
      path_or_hf_repo=\"mlx-community/whisper-large-v3-mlx\", language=\"ru\")[\"text\"])"'
```

## Related

- [whisper-server (ubuntu-home)](../backend/voice-service/deploy/whisper-server/README.md) — код и деплой STT-сервиса
- [mac-client](../backend/voice-service/deploy/mac-client/) — установщик и Stop hook для мака
- [vds-wrappers](../backend/voice-service/deploy/vds-wrappers/README.md) — чем отвечаем в VK
- [сравнение моделей](../bench/whisper-accuracy/comparison-2026-08-01.md) — turbo против large-v3 на одном корпусе

[← docs/INDEX.md](INDEX.md)
