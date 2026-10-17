# Конспект участника по Подлодке AI Crew 4 (после afterparty)

Прислал Sergey 17.10.2026 — чей-то конспект «как обещал вчера на afterparty» +
анонс Maestro. Сохранено дословно, автор не указан.

---

# Submarine AI Crew 4 — заметки с сессии конференции

## Скилы — попробовать
| Скил | Ссылка | Заметка |
|---|---|---|
| superpower | https://github.com/obra/superpowers | |
| grill-me | https://github.com/andrianov28/grill-me | |
| codegraph | https://github.com/colbymchenry/codegraph | |
| codebase-memory | https://github.com/DeusData/codebase-memory-mcp | не очень, путает агента |
| openspec | — | ссылки нет |
| microcompact | — | ссылки нет |
| agent browser от vercel | — | ссылки нет |
| rtk (Rust Token Killer) | — | снижает потребление токенов |

### Каталоги скилов / реестры
- https://github.com/anthropics/skills
- https://github.com/reason-machines/claude-code-skills
- https://github.com/davila7/claude-code-templates
- https://www.skills.sh/
- https://hermes-ai.net/skills/
- https://tessl.io/registry
- https://openharness.ai/samples.html
- https://www.jevradar.com/

## Оркестраторы
- curator — https://github.com/relux-works/curator
- maestro — https://github.com/wad-jet/maestro
- afactory — https://github.com/PakhomovAlexander/afactory
- agentflow — https://github.com/reforma-ai/agentflow
- goga — https://github.com/qarium/goga
- paperclip — https://github.com/paperclipai/paperclip
- orca — https://github.com/stablyai/orca/tree/main
- bb — https://getbb.app/

## Модели и локальный инференс
- Qwen3.8-Flash-Next — https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/tree/main
- Qwen3.8-27B
- Qwen3.6-35B-A3B
- GLM-5.3-Flash-NVFP4 — https://huggingface.co/nvidia/GLM-5.3-Flash-NVFP4/tree/main
- llama.cpp v0.6.0 — https://github.com/ggml-org/llama.cpp/releases/tag/v0.6.0

### Бенчи
- llama sweep
- llama bench

### Шлюз для множества моделей по единому протоколу (AI gateway)
- LiteLLM

## Инструменты и фреймворки
- beads — https://github.com/gastownhall/beads
- specadoc — https://github.com/andreipan/specadoc
- playwriter — https://playwriter.dev/
- maestro (mobile UI testing, не оркестратор) — https://github.com/mobile-dev-inc/maestro
- claude-smart — https://github.com/ReflexioAI/claude-smart
- Strata — https://github.com/Niko1221/Strata
- SimpleEn-RU — https://github.com/GregoryPletnev/SimpleEn-RU
- anything-llm — https://github.com/Mintplex-Labs/anything-llm
- langflower — https://github.com/earthdmitriy/langflower
- open-code-review — https://github.com/alibaba/open-code-review
- hermes-agent — https://github.com/NousResearch/hermes-agent
- afm — https://github.com/akopichin/afm

## Материалы
- Презентация «agentic-setup-fall-2026» — https://grably.tech/slides/agentic-setup-fall-2026/#slide=16.1
- Видео — https://www.youtube.com/watch?v=Egr_TQ4Z-hY
- LangChain / AI-агенты на Python — https://thecode.media/langchain-ai-agenty-python/
- softwarearchitectureweekly.substack.com
- architecture.md — https://architecture.md/

## Ссылки по теме ИИ — полезные каналы
- ИИшенка — https://www.youtube.com/watch?v=wJ9pIsUT_7c
- Run Bot Run — https://www.youtube.com/watch?v=YtheC1qr6VI
- Alexey Andreevsky — https://www.youtube.com/@AlexeyTripleA

---

## Анонс Maestro (от автора)

Maestro — оркестратор полного цикла разработки фич и багфиксов в OpenCode.
Связывает разрозненные скиллы (включая superpowers) в единый конвейер с HITL-гейтами:
- сквозной pipeline: brainstorming → spec → plan → SDD → review → docs;
- HITL-гейты на spec, pre-PR, merge; санитайзинг промптов, audit-логи, permissions OpenCode;
- 7 специализированных агентов (custodian, reviewer, sanitizer и др.), команда /test-agents;
- быстрый маршрут для простых фич без spec; опциональная память сессий (векторный поиск);
- установка maestro-install.sh, документация по Diátaxis; рабочий язык — русский.

Репозиторий: https://github.com/wad-jet/maestro
