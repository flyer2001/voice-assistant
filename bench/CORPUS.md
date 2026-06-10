# Bench corpus — 8 транскриптов для записи

**16 файлов на iPhone Voice Memos: каждый текст × {quiet, noisy}.**

Quiet = дома, окно закрыто, без вентилятора рядом.
Noisy = улица с машинами / кафе с фоном.
Темп — естественный, ~150 wpm. Один файл = один текст.

Naming: `<id>-<env>.m4a` (например `2a-quiet.m4a`, `3b-noisy.m4a`).

---

## Set 1 — чистая русская речь (baseline)

### `1a-quiet.m4a` / `1a-noisy.m4a` — 5s

> Сегодня вторник, нужно успеть в магазин — купить молоко, хлеб, помидоры и заехать на заправку.

### `1b-quiet.m4a` / `1b-noisy.m4a` — 15s

> Сегодня вторник, к вечеру обещают дождь, поэтому нужно успеть в магазин, купить молоко, хлеб, помидоры, заехать на заправку, забрать сына с тренировки около семи и не забыть позвонить маме на обратной дороге.

---

## Set 2 — RU + EN dev-команды

### `2a-quiet.m4a` / `2a-noisy.m4a` — 5s

> Запушь ветку feature auth в GitHub и открой pull request на ревью.

### `2b-quiet.m4a` / `2b-noisy.m4a` — 15s

> Запушь текущую ветку feature-auth в GitHub, открой pull request на main, добавь Сергея в ревьюверы, и проверь что прошли все CI чеки перед мёрджем — линт, юнит-тесты и тайп-чек.

---

## Set 3 — observability / incident triage

### `3a-quiet.m4a` / `3a-noisy.m4a` — 5s

> Открой дашборд api-latency в Grafana и покажи пятый процентиль.

### `3b-quiet.m4a` / `3b-noisy.m4a` — 15s

> Открой дашборд api-latency в Grafana за последний час, посмотри есть ли всплески по пятому процентилю, если есть — открой логи пода auth-service в staging кластере и пришли мне трейс ошибки.

---

## Set 4 — версии, числа, аббревиатуры

### `4a-quiet.m4a` / `4a-noisy.m4a` — 5s

> Обнови WhisperKit до версии ноль точка восемь точка три.

### `4b-quiet.m4a` / `4b-noisy.m4a` — 15s

> В Package.swift обнови WhisperKit до версии ноль точка восемь точка три, перезапусти build через swift build, и если зелёный — закомить с сообщением update WhisperKit to zero dot eight dot three.

---

## Checklist

- [ ] `1a-quiet`  · `1a-noisy`
- [ ] `1b-quiet`  · `1b-noisy`
- [ ] `2a-quiet`  · `2a-noisy`
- [ ] `2b-quiet`  · `2b-noisy`
- [ ] `3a-quiet`  · `3a-noisy`
- [ ] `3b-quiet`  · `3b-noisy`
- [ ] `4a-quiet`  · `4a-noisy`
- [ ] `4b-quiet`  · `4b-noisy`

**Передача файлов:** AirDrop iPhone → mac-home, потом `scp ~/voice-bench/*.m4a vds:/root/projects/voice/assets/bench/raw/`.
