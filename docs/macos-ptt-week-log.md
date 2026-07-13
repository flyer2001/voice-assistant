# macOS PTT — week dogfooding log

**Cycle:** ______ (YYYY-MM-DD → YYYY-MM-DD)

Заполнять руками в течение недели + один финальный проход.

---

## Quantitative (из JSONL)

Скрипты см. `clients/macos-ptt/README.md` секция «Logging analysis».

| Метрика | Значение |
|---|---|
| Total PTT sessions | |
| Total records (successful) | |
| Errors (upload/http/mic) | |
| Too-short (accidental) count + % | |
| Upload latency p50 | |
| Upload latency p95 | |
| STT latency p50 (stt_ms field) | |
| End-to-end press→notification p50 | |
| End-to-end p95 | |

## Qualitative (руками)

### Комфорт клавиши F19 (1-5)

Скор: __ / 5

Notes:

### Latency subjective (1=неощутимо, 5=бесит)

Скор: __ / 5

Notes:

### Ошибка транскрипции (сравнение с тем что говорил)

Примеры плохих транскрипций:
- Сказал «...» → получил «...»
- ...

Часто путаемые слова / термины:

### Сценарии реального использования

- [ ] Coding (mac-home сидя)
- [ ] Cooking / уборка (руки заняты)
- [ ] Прогулка / улица (шум ветра)
- [ ] Driving (руки на руле)
- [ ] Meeting / call
- [ ] Other: ___

### False triggers

Ситуации где случайно нажал F19:
- ...

### Missing features

Что больше всего мешает без:
- [ ] Silence-timer (пауза внутри одного PTT)
- [ ] Chord gestures (double-click cancel, triple-click focus switch)
- [ ] Cancel gesture (отмена без отправки)
- [ ] Silent-mode (без `say`)
- [ ] Volume level indicator
- [ ] Assistant-reply (не только echo)
- [ ] VK-forward (переслать в VK бота)
- [ ] Other: ___

### Одна главная боль

___

---

## Decision

**Continue Phase 7 (заказ CoreS3 + гарнитуры)?** (Y / N)

**Reasoning:**

**Что менять в MVP-scope перед следующей итерацией:**

**Что переносить в hardware-версию (уже понятно, не надо переиграть на Mac):**
