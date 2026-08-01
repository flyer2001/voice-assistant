# VDS wrappers

Скрипты из `/usr/local/bin/` на VDS. Их зовут Claude-сессии, чтобы ответить
Sergey'ю в VK и переключить фокус голосового ввода.

До 2026-08-01 они существовали **только** в `/usr/local/bin` — потеря VDS
означала потерю всей обвязки. Здесь снимок для версионирования.

| файл | что делает |
|---|---|
| `voice-reply` | текст в VK |
| `voice-reply-tts` | Yandex TTS → oggopus → VK как голосовое |
| `voice-reply-both` | текст + голос (default для ответа на войс) |
| `voice-focus` | переключить фокус голосового ввода на проект |
| `voice-focus-clear` | сбросить фокус → маршрут к диспетчеру |

## Секреты

В скриптах их нет — читаются из окружения VDS на месте:

- `/etc/yandex_speechkit.env` → `API-KEY`
- `/etc/vk-bot.env` → `VK_BOT_TOKEN`

Эти файлы в git не попадают и не должны.

## Установка / синхронизация

```bash
install -m 755 voice-* /usr/local/bin/
```

Правишь прод — обнови копию здесь, иначе разъедутся. Проверить дрейф:

```bash
for f in voice-reply voice-reply-tts voice-reply-both voice-focus voice-focus-clear; do
  cmp -s "$f" "/usr/local/bin/$f" && echo "ok    $f" || echo "DRIFT $f"
done
```

`cmp`, не `diff` — вывод `diff` через Bash сжимается hook'ом rtk и может
показать «identical» на различающихся файлах.

## Про алиасы voice-focus

`ассистент`, `диспетчер`, `assistant`, `dispatcher` → делегируют в
`voice-focus-clear`. Это намеренно: диспетчер и есть маршрут по умолчанию
(`VOICE_TARGET_CWD`), отдельным фокусом он не выражается.

[← ../README.md](../README.md)
