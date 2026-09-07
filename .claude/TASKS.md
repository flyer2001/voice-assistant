# TASKS — voice

> Active sprint. Only open items: `[ ]` open, `[~]` in-progress, `[!]` blocked.
> Каждый пункт исполним сейчас и имеет done-signal. Аспирационное и
> заблокированное железом → [`BACKLOG.md`](BACKLOG.md).
> Закрытые задачи — в [`CHANGELOG.md`](CHANGELOG.md) (prepend через `/endsession`).

Сделано: v0.0 foundation, W1–W5 STT bench, backend B1–B9, S1/S2 Speech+Happy,
MVP_thin² VK voice E2E (2026-06-23), Whisper systemd на ubuntu-home,
async callback + TTS dual channel (2026-07-05), Phase 6 focus routing
(2026-07-05), voice-agent-mac full loop E2E (2026-07-17), backend snapshot
в git (2026-07-18) — детали в CHANGELOG.

---

## voice-agent-mac — доводка после E2E green

Loop работает: mic → mlx-whisper local → VDS → inject в Claude-сессию →
Yandex TTS → mac speaker.

- [ ] **E2E dogfood** — живая проверка full loop, 5 фраз подряд без ручного
      вмешательства. Окружение восстановлено 2026-08-01 (`install-mac.sh`):
      venv `~/.venvs/voice-agent` + mlx-whisper, ffmpeg 8.1.2, t3 в `~/bin`,
      враппер `~/bin/voice-agent-t3`.
      ⚠️ **Запускать только локально в Terminal.app на маке.** Через ssh
      re-exec в Aqua-домен падает с `Could not switch to audit session:
      Operation not permitted`, когда экран заблокирован — а без Aqua нет
      микрофона. Я проверить loop сам не могу, нужен ты за компом
- [ ] **Whisper accuracy — разметить корпус.** Harness готов
      ([`bench/whisper-accuracy/`](../bench/whisper-accuracy/README.md)), 24 клипа
      прогнаны через turbo, аудио выложено. Осталось руками заполнить `truth` в
      `ground-truth.jsonl` (слушать по ссылкам) → `./run.py report` даст WER.
      Sergey, это ~5 минут прослушивания
- [ ] **Whisper accuracy на боевых фразах** — текущий корпус весь тестовый
      («тестовое сообщение», «проверка связи»), WER по нему занижен. Нужны
      реальные RU+EN mixed запросы с техтерминами. Накопится сам при dogfood
- [ ] **`Веронись` / `Вертись` — понижено, не чинить постобработкой.**
      Проверено 2026-08-01: regex-матчинга голосовых команд в коде нет вообще
      (единственное совпадение — текст ошибки). Фокус переключается slash-
      командой или моделью, читающей транскрипт, а модель искажение понимает.
      То есть ломается только читаемость лога, а не поведение. Постобработка
      добавила бы риск ложных правок ради несуществующей проблемы.
      Возвращаться, если появится код, матчащий команды по строке
- [ ] **Stop hook — живая проверка после фикса** (2026-08-01 логика починена,
      7 тестов green, но E2E с реальным маком не гонялся). Done: голос → ответ
      с tool-вызовами внутри → TTS прочитал финальный текст
- [!] **Демон записи** — blocked одной цепочкой с wake word. Без него это
      бесконечный цикл «записал 5с → отправил», поток мусора в сессию.
      Делать только после Porcupine.
      NB: демон **воспроизведения** сделан отдельно 2026-09-02 и не блокирован
      (`install-player.sh`) — он только играет ответы, не пишет
- [!] **Wake word Porcupine «Алёнка»** (US-1) — blocked: нужен access key +
      train keyword (console.picovoice.ai, ~5 мин). Сейчас запуск вручную

## mac-home — окружение

- [ ] `sudo pmset -a sleep 0 disksleep 0 tcpkeepalive 1` — на 2026-08-01
      sleep=20, tcpkeepalive=0. Только Sergey: sudo на маке требует пароль,
      беспарольного нет
- [!] Mount voice-repo через sshfs — blocked: нужен macFUSE (системное
      расширение → пароль + разрешение в System Settings + reboot). Только
      Sergey. Альтернатива без блокера — отдельный `git clone` на маке

## Phase 7 — закупка железа (корзина собрана 2026-08-29)

- [ ] **Переходник на две пайки: гнездо 3.5 (Tip+Sleeve) → штекер TRS в мак.**
      Гарнитура на рации работает (проверено 2026-08-29), а через покупной
      TRS→TRRS молчит — дело в разводке. Done: слышно голос из мака. Это
      закрывает вопрос, нужен ли усилитель для связки с телефоном
- [ ] **Прозвонить землю гарнитуры** — `Sleeve` 3.5мм против `Sleeve` 2.5мм.
      От этого зависит, заходит ли BTL-выход MAX98357A напрямую или нужна
      развязка. См. открытый вопрос в [`docs/mcu-client.md`](../docs/mcu-client.md)
- [ ] **Правки корзины перед оплатой:** 2.5мм разъёмы взяты mono/вилками —
      нужен 2.5mm **stereo TRS female panel-mount** (без Ring не работает PTT).
      Подтвердить, что модуль ES8388 — именно M5Stack Module Audio с M-Bus,
      а не generic breakout. Клавиатура для Tab5 к этому проекту не относится

## Live-транскрипция (дедлайн 13.09, конференция 14–18.09)

Ядро готово и проверено сквозным прогоном на реальном звуке:
[`deploy/live-transcribe/`](../backend/voice-service/deploy/live-transcribe/README.md),
обоснование — [`docs/live-transcribe.md`](../docs/live-transcribe.md).

- [ ] **Sergey: включить obs-websocket на mac-work** — Настройки OBS →
      Инструменты → obs-websocket, поставить галочку. Порт 4455 уже прописан.
      Без этого не написать управление записью с VDS
- [ ] **Sergey: добавить в OBS источник системного звука** (macOS Screen
      Capture с включённым звуком). Один раз, дальше сцена сохраняется
- [ ] Написать capture-obs (управление записью по websocket) — после того,
      как сервер включён
- [ ] Прогнать полный цикл на живом звуке доклада, померить задержку
- [ ] Собрать словарь техтерминов под iOS/AI-тематику и проверить на
      реальном звуке, а не вслепую (эффект модель-зависимый)
- [ ] **Записи прошлой Подлодки про AI-процессы** — отобрать сессии,
      прогнать `transcribe_file.sh`, дальше по шагам сужения из
      [`docs/live-transcribe.md`](../docs/live-transcribe.md) до гипотез в
      `_project-hub`. Нужно от Sergey: где лежат записи и есть ли к ним доступ
- [ ] BlackHole на mac-home для собеседований — `brew install --cask
      blackhole-2ch` плюс Multi-Output Device. Нужен пароль Sergey

## Станция Стрит как устройство ввода (ресёрч 2026-09-06)

Идея Sergey. Технически работает, вечер работы, всё нужное есть. Но годится
**только для коротких команд**: управления микрофоном в API нет, пауза на
размышление обрывает реплику, длинный монолог не продиктовать. Второй канал
к VK, не замена. Детали: [`docs/alice-skill-input.md`](../docs/alice-skill-input.md).

**Решение Sergey не принято** — браться, только если короткие команды нужны
сами по себе.

- [x] Маршрут `/v1/alice/<секрет>` — сделан, задеплоен, проверен сквозным
      прогоном (HTTPS → Caddy → инжект по фокусу). 17 тестов
- [ ] **Sergey: создать приватный навык в консоли Диалогов**, указать webhook
      с секретом из `/etc/voice-backend.env`. Пошагово — в
      [`docs/alice-skill-input.md`](../docs/alice-skill-input.md)
- [ ] Прописать `ALICE_SKILL_ID` в env после создания навыка и перезапустить
- [ ] Живая проверка с колонки, подобрать активационное имя (Алиса не должна
      путать его с другими навыками)

## Phase 6 F5 — pattern analyzer

Spec проверен на живых данных 2026-08-01 и поправлен (v1.0.0):
[`docs/voice-patterns.md`](../docs/voice-patterns.md). Запуск отложен —
в `audit.jsonl` 26 записей и все тестовые, порог = 100 нетестовых.

- [ ] Прогнать анализ когда накопится корпус. Проверка порога — команда
      в секции Preconditions спека

---

## Open questions / risks (live)

- VK rate limit / ToS — Sergey ↔ bot DM only, не group. ~100 msg/day fine.
  См. memory `reference_vk_bot_contracts.md`
- VK `audio_message_transcript` async event skip'ается в MVP — Whisper всегда
  работает когда `state != "done"`. Перепроверить если Whisper под нагрузкой
- Audit JSONL eviction policy = NONE (Phase 0 SP3). ~180KB/msg, OK на год
