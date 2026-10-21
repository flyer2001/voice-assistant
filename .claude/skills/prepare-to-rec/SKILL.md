---
name: prepare-to-rec
description: Подготовить эфир к живой транскрипции и убедиться, что он реально идёт — ubuntu-home в Ubuntu, whisper жив, хвост поднят на твой sid, в чат ушло «🔴 ЗАПИСЬ И ТРАНСКРИБАЦИЯ ЭФИРА ЗАПУЩЕНА». Триггеры — «prepare to rec», «готовь запись», «стартую созвон», «сейчас дейлик/груминг», «включаю OBS».
version: 1.0.0
bumped: 2026-10-21
bumped_reason: "initial — заявка Sergey 21.10 после эфира, где pre-flight и подъём хвоста делались руками шесть раз подряд, и дважды хвост успел взять старую запись с нуля."
---

# prepare-to-rec

Полная механика, грабли и диагностика — `~/.claude/docs/live-transcribe.md`.
Здесь только последовательность и то, чего в доке нет.

## 1. Pre-flight — три проверки одной командой

```bash
/root/projects/agentops/bin/detect-home-os.sh
curl -s -o /dev/null -w "whisper:%{http_code}\n" --max-time 10 http://192.168.88.13:8000/health
~/projects/assistant/scripts/inject/resolve-happy-sid.sh
ps -eo pid,ppid,lstart,cmd | grep -E "[l]ive_tail\.sh|[n]anny\.sh"
```

- `windows` или `offline` → переключить и **дождаться**:
  ```bash
  HOST_LEASE_HOLDER=voice /root/projects/agentops/bin/os-switch.sh ubuntu --wait
  ```
  Отказ по аренде называет держателя — договариваться, не форсить: `--force`
  аренду не снимает, а форс из Windows может оставить машину выключенной.
- `whisper` не 200 → `live_tail.sh` сам делает pre-flight и падает с
  инструкцией; смотреть раздел про CUDA в доке.
- Чужой хвост или нянька с прошлой сессии → **гасить по pid**, иначе блоки
  уедут в архивный sid, а рядом с твоим хвостом дадут дубли.

## 2. Поднять хвост и няньку

sid подставить свой, из `resolve-happy-sid.sh`. `VOICE_CHUNK_S=30` — блоки по
30 с: на 15 с половина фраз рвётся на границе.

```bash
setsid nohup env \
  VOICE_REC_DIR='$HOME/Movies' \
  VOICE_CHUNK_S=30 \
  VOICE_INJECT_EVERY=1 \
  VOICE_INJECT_SID=<свой sid> \
  VOICE_PROMPT_FILE=/root/projects/voice/bench/work/prompt.txt \
  /root/projects/voice/backend/voice-service/deploy/live-transcribe/live_tail.sh \
  mac-work /srv/voice-private/live >> /srv/voice-private/live/tail.log 2>&1 < /dev/null &

cd /root/projects/voice && setsid nohup env \
  VOICE_INJECT_SID=<свой sid> VOICE_CHUNK_S=30 VOICE_INJECT_EVERY=1 \
  VOICE_PROMPT_FILE=/root/projects/voice/bench/work/prompt.txt \
  backend/voice-service/deploy/live-transcribe/nanny.sh \
  >> /srv/voice-private/live/nanny.log 2>&1 < /dev/null &
```

`bench/work/prompt.txt` — рабочая терминология Авито. Другая тема — свой файл.

⚠️ **Хвост берёт любой свежий `.mov` (фильтр `-mmin -10`) с позиции 0.**
Если только что закончилась предыдущая запись, он подхватит её и перегонит
заново — это десятки дублей в чат. Перед подъёмом хвоста:

```bash
touch "/srv/voice-private/live/.done-<имя прошлой записи>.mov"
```

Маркер `.done-` — единственный штатный способ сказать «эту не трогай».

⚠️ Второй процесс `live_tail.sh` с **ppid первого** — это дочерний сабшелл, а
не дубль. Дубль — это два процесса с ppid 1. Не гасить вслепую.

## 3. Доказать, что транскрипция идёт

Живой процесс доказательством **не является**. Доказательство — строка
`N символов` в логе и блок с текстом в чате.

```bash
tail -3 /srv/voice-private/live/tail.log
```

Ждёт — `жду новой записи...`. Подхватил — `запись: /Users/.../<имя>.mov`,
дальше пойдут чанки.

Если OBS ещё не запущен — дождаться подхвата, не опрашивая лог в цикле:

```bash
# run_in_background: true
until grep -q "запись: /Users" <(tail -5 /srv/voice-private/live/tail.log); do sleep 10; done
```

Нет текста за две минуты после начала речи — идти в диагностику по доке,
а не ждать дальше. Серия строк `тишина` подряд — тоже повод идти, а не ждать.

## 4. Сказать в чат

Только после того, как увидел реальный текст (или, если эфир ещё не начался,
строку `запись: ...`):

> 🔴 **ЗАПИСЬ И ТРАНСКРИБАЦИЯ ЭФИРА ЗАПУЩЕНА**

Рядом, коротко: имя записи, размер чанка, что sid сверен, что хвост один и
нянька на месте, путь к конспекту.

Если эфир ещё не начался, так и сказать: подхват есть, текста пока нет,
первый блок покажу.

## 5. Дальше — режим слушателя

Блоки не комментировать построчно. Вопросы Sergey'ю — **текстом**, не голосом:
он в эфире. Попадания — в `/srv/voice-private/live/questions.md`.

Галлюцинации на тишине («Спасибо», «Продолжение следует», перечисления имён,
титры несуществующих авторов) — не реплики, не разбирать.

Разбор после эфира — скилл `meeting-digest`.

---

← [prepare-to-rec] · рядом: `meeting-digest` (разбор после эфира) ·
[live-transcribe.md](../../../../.claude/docs/live-transcribe.md)
