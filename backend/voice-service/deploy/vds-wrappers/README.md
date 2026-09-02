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
| `voice-say` | режим живого диалога: текст в VK + голос сразу на mac-home |

## voice-say — диалог без нажатий

```bash
voice-say <peer> "<текст>" ["<короткий текст для озвучки>"]
```

Текст уходит в VK (можно читать), голос звучит на маке сам. Голос в VK
намеренно не дублируется — за компом его всё равно не открывают, а лишний
синтез стоит денег и секунд. Нужен голос именно в VK — `voice-reply-both`.

Третий аргумент нужен, когда полный ответ длинный или полон путей: в VK
уходит полный, вслух короткий.

Требует плеера на маке — `deploy/mac-client/install-player.sh`. Если мак спит,
текст всё равно уходит, в ответе будет `"mac":"failed"`.

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

## Тесты

```bash
./test_voice_focus.sh        # 21 проверка alias-таблицы и записи focus.json
./test_voice_reply_tts.sh    # 13 проверок цепочки TTS→VK, без сетевых вызовов
```

Оба гоняют настоящие скрипты, но безвредно: `curl` подменяется заглушкой
через PATH, секреты — фикстурами, `focus.json` пишется во временный каталог.
Ни одного голосового Sergey'ю не уходит.

Пути параметризованы через env (`VOICE_REPLY_TTS`, `VOICE_FOCUS_PATH`,
`VOICE_PROJECTS_DIR`, `YANDEX_ENV_FILE`, `VK_ENV_FILE`) — дефолты совпадают
с продом, так что поведение не меняется.

## Про алиасы voice-focus

`ассистент`, `диспетчер`, `assistant`, `dispatcher` → делегируют в
`voice-focus-clear`. Это намеренно: диспетчер и есть маршрут по умолчанию
(`VOICE_TARGET_CWD`), отдельным фокусом он не выражается.

[← ../README.md](../README.md)
