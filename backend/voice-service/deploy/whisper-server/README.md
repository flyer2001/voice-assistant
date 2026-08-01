# whisper-server (ubuntu-home)

STT-релей для VK-пути. `faster-whisper-large-v3-turbo` на CUDA fp16.

- **Хост:** ubuntu-home, `192.168.88.13:8000` (виден с VDS через WireGuard)
- **Юнит:** `whisper.service`, `User=flyer2001`
- **Рабочий каталог:** `/mnt/win-share/Users/Serg/whisper-server/`
  (NTFS-шара, общая с Windows-половиной dual-boot)

Файл живёт на шаре, а не в этом репозитории — здесь **копия для
версионирования**. При правке: обновить обе, иначе разъедутся.

```bash
scp server.py ubuntu-home:/mnt/win-share/Users/Serg/whisper-server/server.py
ssh ubuntu-home 'sudo systemctl restart whisper.service'
curl -s http://192.168.88.13:8000/health | jq .
```

Модель грузится ~20с, health до этого не отвечает.

## API

```
POST /transcribe   multipart: audio, lang_hint?, initial_prompt?
  → {text, lang, duration_s, stt_ms, prompt_used}
GET  /health       → {ok, model, device, compute_type, default_prompt_len}
```

## Про initial_prompt

Добавлен 2026-08-01. **По умолчанию выключен** — и это осознанно.

Прогон корпуса ([comparison](../../../../bench/whisper-accuracy/comparison-2026-08-01.md)):
на turbo промпт дал 2 улучшения и 2 регресса из 24 клипов. Опасен характер
регресса — распознавание притягивается к словам из словаря:

```
без промпта:  Фокусируйся на voice.sess     ← верно
с промптом:   Фокусируйся на voice-agent    ← voice-agent есть в словаре
```

Для команд переключения фокуса это хуже исходной ошибки: имена проектов
начнут «примагничиваться» друг к другу.

На large-v3 (mac-агент) тот же промпт улучшил 15 клипов из 24 — там он
включён и оправдан. Разные модели реагируют по-разному, поэтому решение
оставлено клиенту.

Включить default осознанно: `WHISPER_INITIAL_PROMPT=<текст>` в окружении
юнита. Разово — передать `initial_prompt` в форме запроса.

[← ../README.md](../README.md)
