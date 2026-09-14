# Как пишем доклад — порядок на сегодня

## Во время доклада (Sergey, два действия)

1. **Перед началом** — открыть OBS, нажать «Начать запись». Всё.
   Websocket не нужен, пишем руками. Имя файла OBS содержит время старта —
   оно потом пригодится для склейки.
2. **По ходу** — интересный слайд: `⌘⇧4` (или `⌘⇧3` весь экран). Снимки
   падают на Desktop, больше ничего делать не надо.

Остановить запись по окончании. Сказать мне «доклад кончился» любым каналом.

## После доклада (voice-сессия, сама)

```bash
# забрать запись и скриншоты с mac-work
scp mac-work:"~/Movies/2026-09-14*.mkv" bench/podlodka/2026-09/raw/
scp "mac-work:~/Desktop/Screenshot_17*.png" bench/podlodka/2026-09/shots/

# расшифровать со словарём конференции
VOICE_WHISPER_URL=http://192.168.88.13:8000 \
VOICE_INITIAL_PROMPT="$(cat bench/podlodka/2026-09/prompt.txt)" \
  backend/voice-service/deploy/live-transcribe/transcribe_file.sh \
  raw/<файл>.mkv bench/podlodka/2026-09/transcripts/14-metrics.md

# прикрепить скриншоты (start — из имени файла записи OBS)
backend/voice-service/deploy/live-transcribe/attach_screenshots.py \
  bench/podlodka/2026-09/transcripts/14-metrics.md \
  bench/podlodka/2026-09/shots/ --start "2026-09-14 11:00:05"
```

Дальше разбор субагентом на haiku по схеме прошлой Подлодки, свод с
вопросами, которые готовил myRep до доклада: подтвердилось / опроверглось.

## Контекст до доклада

Готовит myrep-29 (запрошено 09:20): заметка «как не читать книги», гипотезы
из прошлой Подлодки, 3-5 вопросов спикеру. Ответ придёт сообщением.
