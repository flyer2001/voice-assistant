# TTS Bench Survey — оценки 1-5

Прослушай каждую фразу подряд через все 5 провайдеров, проставь оценки. Замени `_` на цифру.

## Шкала

| Балл | Естественность | Адекватность контексту |
|---|---|---|
| 5 | Не отличить от человека | Идеально попало (эмоция/тон/смысл) |
| 4 | Очень хорошо, слабый "робот" | Хорошо, мелкие отклонения |
| 3 | Прилично, явно синтетика | Передаёт смысл, без эмоции |
| 2 | Понятно, но неприятно | Сильное искажение смысла |
| 1 | Сложно понять / каша | Не работает (искажение, не на том языке) |

---

## p1-cmd-ru — command_ru

> «Сколько денег на счету?»

**Что проверяем:** Baseline RU прозодия, короткий вопрос

### apple/Milena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p1-cmd-ru.mp3

- Естественность: 2 /5
- Адекватность контексту: 3 /5
- Заметка (опц.): не правильное ударение 

### yandex/alena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p1-cmd-ru.mp3

- Естественность: 5 /5
- Адекватность контексту: 5 /5
- Заметка (опц.):

### piper/ru_RU-irina-medium
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p1-cmd-ru.wav

- Естественность: 5 /5
- Адекватность контексту: 4 /5
- Заметка (опц.): неправильно ударение сче`ту

### silero/baya
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p1-cmd-ru.wav

- Естественность: 4 /5
- Адекватность контексту: 4 /5
- Заметка (опц.): неправильно ударение сче`ту

### xtts-v2/Claribel Dervla
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p1-cmd-ru.wav

- Естественность: 5 /5
- Адекватность контексту: 4 /5
- Заметка (опц.): неправильно ударение сче`ту

---

## p2-codemix-tech — codemix_tech

> «Push the API endpoint, refactor the adapter.»

**Что проверяем:** Чистый EN с тех. терминами — проверка англ. голоса

### apple/Milena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p2-codemix-tech.mp3

- Естественность: 1 /5
- Адекватность контексту: 1 /5
- Заметка (опц.): вообще не разобрать английский слов, на ломаном русском

### yandex/alena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p2-codemix-tech.mp3

- Естественность: 5 /5
- Адекватность контексту: 5 /5
- Заметка (опц.): классно, слышится русский акцент, но слова произносятся правильно и понятно

### piper/ru_RU-irina-medium
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p2-codemix-tech.wav

- Естественность: 4 /5
- Адекватность контексту: 2 /5
- Заметка (опц.): плохо произносимо, сложно разобрать

### silero

_(нет семпла — пропущено провайдером)_

### xtts-v2/Claribel Dervla
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p2-codemix-tech.wav

- Естественность: 5 /5
- Адекватность контексту: 5 /5
- Заметка (опц.): отличное произношение прям английская дикция

---

## p3-codemix-mid — codemix_ru_en

> «Bro, я серьёзно, ты опять забыл deploy запушить?»

**Что проверяем:** RU + EN терминs в одной фразе — главный тест для XTTS / ElevenLabs

### apple/Milena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p3-codemix-mid.mp3

- Естественность: 2 /5
- Адекватность контексту: 3 /5
- Заметка (опц.): относительно не плохо

### yandex/alena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p3-codemix-mid.mp3

- Естественность: 5 /5
- Адекватность контексту: 5 /5
- Заметка (опц.): только утадерение запу'шить неправильое

### piper/ru_RU-irina-medium
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p3-codemix-mid.wav

- Естественность: _ /5
- Адекватность контексту: _ /5
- Заметка (опц.):

### silero/baya
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p3-codemix-mid.wav

- Естественность: 4 /5
- Адекватность контексту: 4 /5
- Заметка (опц.):

### xtts-v2/Claribel Dervla
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p3-codemix-mid.wav

- Естественность: 4 /5
- Адекватность контексту: 5 /5
- Заметка (опц.):

---

## p4-alert — alert

> «Внимание! Критическая ошибка в production-сервисе.»

**Что проверяем:** Прозодия тревоги, exclamation, дефис в составном слове

### apple/Milena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p4-alert.mp3

- Естественность: 1 /5
- Адекватность контексту: 2 /5
- Заметка (опц.): ужасное произношение

### yandex/alena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p4-alert.mp3

- Естественность: 5 /5
- Адекватность контексту: 5 /5
- Заметка (опц.):

### piper/ru_RU-irina-medium
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p4-alert.wav

- Естественность: 4 /5
- Адекватность контексту: 5 /5
- Заметка (опц.):

### silero/baya
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p4-alert.wav

- Естественность: 4 /5
- Адекватность контексту: 2 /5
- Заметка (опц.): не произнесла production слово

### xtts-v2/Claribel Dervla
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p4-alert.wav

- Естественность: 3 /5
- Адекватность контексту: _ 2 /5
- Заметка (опц.): плохо произноисит 

---

## p5-humor — humor_snark

> «Хе-хе, ну ты, конечно, и придумал. С такой архитектурой далеко не уедешь.»

**Что проверяем:** Юмор / ирония — главный субъективный критерий женский голос

### apple/Milena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p5-humor.mp3

- Естественность: 2 /5
- Адекватность контексту: 3 /5
- Заметка (опц.):

### yandex/alena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p5-humor.mp3

- Естественность: 5 /5
- Адекватность контексту: 5 /5
- Заметка (опц.):

### piper/ru_RU-irina-medium
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p5-humor.wav

- Естественность: 2 /5
- Адекватность контексту: 4 /5
- Заметка (опц.):

### silero/baya
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p5-humor.wav

- Естественность: 3 /5
- Адекватность контексту: 3 /5
- Заметка (опц.): ударения в нескольких местах не правильные

### xtts-v2/Claribel Dervla
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p5-humor.wav

- Естественность: 3 /5
- Адекватность контексту: 5 /5
- Заметка (опц.):

---

## p6-path-numbers — tech_path

> «Транскрипт записан, файл сохранён в /tmp/recording-2026-06-13.caf»

**Что проверяем:** Как читает путь файла, числа, дефисы

### apple/Milena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p6-path-numbers.mp3

- Естественность: 3 /5
- Адекватность контексту: 4 /5
- Заметка (опц.):

### yandex/alena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p6-path-numbers.mp3

- Естественность: 5 /5
- Адекватность контексту: 4 /5
- Заметка (опц.): вот тут в названии файлов накосякичал

### piper/ru_RU-irina-medium
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p6-path-numbers.wav

- Естественность: 4 /5
- Адекватность контексту: 4 /5
- Заметка (опц.):

### silero/baya
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p6-path-numbers.wav

- Естественность: 3 /5
- Адекватность контексту: 1 /5
- Заметка (опц.): не читает английский просто пропускает

### xtts-v2/Claribel Dervla
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p6-path-numbers.wav

- Естественность: 4 /5
- Адекватность контексту: 4 /5
- Заметка (опц.):название файла странно прочитала

---

## p7-soft-question — soft_question

> «Я не уверена в ответе. Может, переформулируешь вопрос?»

**Что проверяем:** Мягкий, доверительный тон — женственность голоса

### apple/Milena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p7-soft-question.mp3

- Естественность: 3 /5
- Адекватность контексту: 4 /5
- Заметка (опц.):

### yandex/alena
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p7-soft-question.mp3

- Естественность: 5 /5
- Адекватность контексту: 5 /5
- Заметка (опц.): отличное интонирование

### piper/ru_RU-irina-medium
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p7-soft-question.wav

- Естественность: 5 /5
- Адекватность контексту: 5 /5
- Заметка (опц.):

### silero/baya
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p7-soft-question.wav

- Естественность: 4 /5
- Адекватность контексту: 5 /5
- Заметка (опц.):

### xtts-v2/Claribel Dervla
🔊 https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p7-soft-question.wav

- Естественность: 2 /5
- Адекватность контексту: 4 /5
- Заметка (опц.):

---

## Свод (заполни после прохождения всех фраз)

| Провайдер | Средняя естественность | Средняя адекватность | Победитель в категории | Главный минус |
|---|---|---|---|---|
| apple | _ /5 | _ /5 | _ | _ |
| yandex | _ /5 | _ /5 | _ | _ |
| piper | _ /5 | _ /5 | _ | _ |
| silero | _ /5 | _ /5 | _ | _ |
| xtts-v2 | _ /5 | _ /5 | _ | _ |

## Финальный выбор

- **Для production v0.1 берём:** _____ (укажи провайдер)
- **Fallback offline:** _____
- **Причина выбора (1 строка):** _____
