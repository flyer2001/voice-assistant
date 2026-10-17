status: done
stage: implement completed
demo: 1

Итоговый отчёт:
- research: out/research-notes.md — REST Search API, точные параметры/поля, фактические HTTP 200, total_count 670 (created) и 3462 (pushed), токен валиден (проверка /rate_limit).
- plan: out/plan.md — архитектура (index.html file:// + collect.mjs), данные, UI, Tests, README.
- implement: app/index.html (одна страница, 3 карточки в ряд по центру, аватары, раскрытие в карточке, ранжирование по звёздам, светлая/тёмная темы, прогресс, запуск при загрузке, masked-поле токена), app/collect.mjs, app/lib/*.mjs, app/test/*.
- Тесты: node --test → 18 pass / 0 fail.
- Реальный запуск: node app/collect.mjs → exit 0; out/state.json: fresh=12, updated=12, даты в пределах 7 дней, звёзды по убыванию (примеры: Fei2411/DeepSeek-Bot 1858, SouravBeraAkaSpeed/xiryn 170, paperclipai/paperclip 102010).
- Токен: из GITHUB_TOKEN (env) в collect.mjs; в браузере masked-поле, только в памяти; скан app/ — литер токена не найдены; значение не логировалось.
- Артефакты: out/research-notes.md, out/plan.md, out/state.json, app/, README.md.
- Исправлений стадий не потребовалось. Отклонение: в браузере env недоступен (зафиксировано research) — токен вводится в masked-поле, сбор стартует автоматически при вводе токена.
follow-up: браузерный автозапуск с env-токеном через генерируемый app/session.js (session-файл = генерируемый артефакт, токен не в коде приложения)
