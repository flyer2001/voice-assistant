# MCU voice client (wearable, non-BT)

**Ветка Phase 7** — альтернатива iOS/macOS клиентам. Носимый девайс:
BC-гарнитура + PTT-кнопка + WiFi через iPhone hotspot / home / Alice /
кафе. Без Bluetooth рядом с головой (у Sergey от BT-наушников быстро
болит голова).

## Constraints (жёсткие)

- **Без BT рядом с головой** (headache trigger)
- **Проводная гарнитура через физический разъём в корпусе** (без свисающих
  adapter'ов)
- **Костная проводимость** (уши свободны для окружения)
- **Костный микрофон** (шумозащита через кость, не воздух)
- **PTT-кнопка на самой гарнитуре**, plus 3-4 chord-паттерна
- **Wake latency ≤ 0.5-1 сек** от нажатия до начала записи
- **Компактность, крепление на одежду**

## Hardware stack (v0.1)

| Компонент | Роль | Цена ₽ | Источник |
|---|---|---|---|
| M5Stack **CoreS3 SE** | ESP32-S3 + 8МБ PSRAM + 2" экран + 500мАч LiPo + USB-C + mic/speaker onboard (fallback) | 5-7к | Ozon |
| M5Stack **Module Audio ES8388** | DAC+ADC codec, M-Bus стек, 2× 3.5mm разъёма (TRRS combo + TRS mic-only) | 2-3к | Ozon / AliExpress |
| **Kenwood K1 female panel-mount socket** | Разъём в корпусе наружу | ~500 | AliExpress |
| Провода + резистор 10 кОм pull-up | Внутренняя разводка + PTT GPIO | копейки | что есть |
| **Vostok HBT-3** (или Baofeng BC-K1 для теста) | BC-наушники + костный mic + PTT, K1 разъём | 8к (Vostok) / 1.5к (Baofeng тест) | krikam.net / AliExpress |
| 3D-печать корпуса | Клипса, прорезь экрана, hole под K1, USB-C | ~200-1000 | сам / 3D-hub |
| **Итого v0.1** | | ~16-20к | |

**НЕ покупать:** CoreS3 Lite (без mic/speaker), CoreS3 full (лишний DinBase),
BT-BC (headache), тактика с Nexus TP-120 (санкции, дорого, громоздко).

## Kenwood K1 authoritative spec

Verified via Baofeng UV-5R schematic (uuki.kapsi.fi, repeater-builder),
Kenwood TK service manuals, wildtalk.com/knowledge-base, ham.stackexchange.

### Big 3.5mm plug (SPEAKER)

| Контакт | Назначение | DC bias |
|---|---|---|
| Tip | SPK+ | **+3-4V DC** от радио BTL amp (половина Vbat) |
| Ring | NC (не используется) | — |
| Sleeve | GND (общий) | 0V |

Radio drives external speaker single-ended off half of BTL amp → **DC
offset present on speaker line**. Tactical headsets (HBT-3 etc.) имеют
**DC-blocking capacitor** in series → блокирует DC bias, пропускает
только AC audio. **DC continuity test мультиметром бесполезен** — cap
даёт ∞/0 даже на живом speaker.

### Small 2.5mm plug (MIC + PTT)

| Контакт | Назначение | DC bias |
|---|---|---|
| Tip | MIC+ | **+3.3V через 4.7-10 kΩ pull-up** (electret bias) |
| Ring | PTT sense | +3.3V pull-up 10 kΩ, замыкание на GND → TX |
| Sleeve | GND (общий с big Sleeve) | 0V |

Expects electret mic 1-2.2 kΩ, -40..-50 dB. HBT-3 (2200 Ω, -45 dB) — в spec.

### PTT

Замыкание Ring 2.5mm на GND (Sleeve 2.5mm или Sleeve 3.5mm — общая GND).

## Wire schema (CoreS3 wearable)

```
┌── Kenwood K1 female sockets (в корпусе) ──────────┐
│                                                    │
│  3.5mm TS/TRS jack panel-mount:                    │
│    Tip     ── SPK+ ──► MAX98357 speaker out+       │
│    Ring    ── NC                                   │
│    Sleeve  ── GND                                  │
│                                                    │
│  2.5mm TRS jack panel-mount:                       │
│    Tip     ── MIC ──► ES8388 mic-in (with bias)   │
│    Ring    ── PTT ──► CoreS3 GPIO X (pull-up 10k) │
│    Sleeve  ── GND                                  │
└────────────────────────────────────────────────────┘
```

**Speaker path:** CoreS3 I2S → MAX98357 (Class-D BTL amp) → K1 speaker
socket → HBT-3. Не через ES8388 headphone out (headphone amp class не
драйвит 10 Ω с достаточным током).

**Mic path:** K1 mic socket → ES8388 mic-in (electret bias через resistor)
→ I2S → CoreS3.

**PTT path:** K1 mic-Ring → GPIO с 10 kΩ pull-up к 3.3V, LOW = нажата.

## Питание и место под доп-батареи

- CoreS3 SE имеет встроенную **500 мАч LiPo** + USB-C зарядку +
  AXP2101 power chip (раздача 3.3V/5V на M-Bus)
- MAX98357/ES8388 запитываются от 5V rail CoreS3 через M-Bus
- **НЕ нужны:** внешние 5V tablet-batteries, TP4056 charging modules,
  отдельный DC barrel jack, доп плюс/минус коннекторы
- **В корпусе достаточно:** отверстие под USB-C сбоку (для зарядки),
  внутренняя разводка проводами от CoreS3 к MAX98357/socket'ам

### Резерв места под extended battery

**Оставить в 3D-корпусе место** под опциональные extra-batteries на
случай если 500 мАч runtime мало (реально 2-3 часа непрерывного диалога,
5-8 часов wake-word idle):

1. **M5Stack Battery Bottom** (+1500 мАч, M-Bus стек снизу) — размер
   54×54×15 мм. Стекается через M-Bus как этаж. Итого стек станет:
   CoreS3 (17мм) + Module Audio (15мм) + Battery Bottom (15мм) = **47мм высоты**.
2. **Или отдельная LiPo pouch** (18650 или 3.7V pouch) — можно припаять
   к JST-connector внутри корпуса, подать в BAT pin CoreS3 (если reroute
   через AXP2101). Runtime × 3-5. Размер под 18650: 18×65 мм.

**Дизайн корпуса:** предусмотреть **посадочное место 54×54×20 мм под
Battery Bottom снизу** ИЛИ **свободный отсек 20×70×10 мм под pouch
LiPo сбоку**. Финальный выбор — после dogfooding текущих 500 мАч.

## Тест iPhone/Mac до CoreS3

### Mic-only через passive adapter (5 мин DIY)

HBT-3 mic электрет 2.2 kΩ совместим с iPhone TRRS CTIA mic input
(bias ~2V/2.2kΩ). Схема passive adapter:

```
HBT-3 2.5mm TRS plug        iPhone 3.5mm TRRS jack (CTIA)
─────────────────           ─────────────────────────────
Tip (MIC)      ────────►    Ring 2 (MIC)
Ring (PTT)     ── NC        (не подключается, игнорируется)
Sleeve (GND)   ────────►    Sleeve (GND)
                            Tip (L), Ring 1 (R) — NC
```

Собрать: 2.5mm TRS male штекер + 3.5mm TRRS male штекер + провод +
пайка. Тест: Voice Memos → запись → есть звук = mic живой.

### Speaker test через amp

Consumer headphone amp'ы (Apple dongle, sound card, FiiO KA1)
**не подойдут** для 10 Ω BC-transducer'а — недостаточный ток,
protection срабатывает. Нужен **speaker-class amp**:

- **PAM8302A** (analog input, 5V USB power) — для Mac 3.5mm out теста
- **MAX98357A** (I2S digital, 3.3-5V) — для CoreS3 финального сборного

## Firmware phases (порядок разработки)

### P1. WiFi + HTTPS POST test (без audio)

- Плата: **MuseLab NanoESP32-C6 v1.0** (у Sergey дома есть). ESP32-C6-WROOM-1-N8,
  512КБ SRAM, 8МБ flash, **без PSRAM**, 2× USB-C (UART + native), RGB LED на
  GPIO8. Repo: https://github.com/wuxx/nanoESP32-C6
- Использовать **native USB-C** (правый) — прошивка без BOOT-нажатия, JTAG debug
- **Firmware language: Swift Embedded** (Swift 6.0+, RISC-V target). ESP32-C6
  — flagship platform Apple/Espressif для Swift Embedded, есть примеры в
  https://github.com/apple/swift-embedded-examples. Shared protocol types с
  macOS-прото (P0). Fallback = Arduino/PlatformIO если Swift toolchain setup
  займёт >1 вечер
- Прошивка: WiFi connect → GPIO wake на кнопке → HTTPS POST test payload
  на voice-backend
- RGB LED как статус-индикатор (idle/wake/upload/error) — замена экрана
- Проверить: TLS handshake latency (cold ~600мс), reconnect стабильность,
  ping-pong с backend

### P2. Audio capture (без PTT logic)

- Плата: CoreS3 SE + Module Audio ES8388
- I2S mic capture 16kHz mono 16-bit в PSRAM ring buffer
- Save 10 sec chunk to SD как WAV, прослушать через тот же jack
- Проверить: SNR onboard mic vs QC25 mic vs (позже) Vostok HBT-3

### P3. Upload flow (audio → backend)

- I2S chunks → Opus encode (arduino-audio-tools или libopus port) → HTTPS
  chunked POST
- Backend принимает Opus/WAV, кладёт в JSONL для проверки
- Проверить: latency от «отпустил» до «на диске VDS», качество разборчивости

### P4. PTT + light sleep + pre-roll

- Light sleep ~1-2 mA + I2S DMA capture в ring buffer **всегда активен**
- GPIO wake от PTT кнопки → beep (50-100мс) → продолжаем чтение буфера
- Pre-roll 200мс до нажатия — user не теряет начало вдоха

### P5. Chord matcher (button UX)

- Библиотека **OneButton** (click / doubleClick / longPress / multiClick)
- State machine поверх для chord (CHC, CCH, CHH и т.п.)
- Bindings (в config JSON на SD/flash):
  - Hold — запись
  - Release + 3-4 сек тишины — отправка
  - Double click — cancel
  - Triple click — cycle focus target
  - Chord CHC (click-hold-click) — reserved
  - Chord CCH — reserved

### P6. TTS reply playback

- Backend возвращает Opus/OGG ответ ассистента
- Decode + I2S OUT → speaker/наушники
- Fallback beep patterns (short/long) для «ok/error/sending»

## Testbench (без Vostok, без Kenwood)

Пока K1/Vostok не приехали, весь flow **отладить на обычной 3.5mm
TRRS гарнитуре** (например Bose QC25 или игровая с mic):

1. **PTT-эмуляция:** два провода — один в GPIO, второй в GND. Замыкаешь
   пальцами / проволокой = «нажатие». Через pull-up резистор.
2. **Audio через QC25:** TRRS штекер QC25 напрямую в Module Audio TRRS
   jack. CTIA стандарт auto-detected. Mic + уши работают.
3. **Полный flow:** отладить P1→P6 без единого custom-адаптера.
4. Когда Vostok HBT-3 приехал — заменить QC25 на Vostok через K1 socket.
   Firmware не меняется.

Airplane adapter Bose QC25 (2× 3.5mm mono) — **НЕ Kenwood** и **НЕ
пригодится** для наших целей.

## macOS parallel prototype (Phase 0)

**Цель:** прожить UX PTT-flow до траты денег на железо. Если через
неделю окажется что «нажать → говорить → ждать → слушать» бесит —
экономия 20к.

**Стек:**

- Swift app (или Python + rumps для tray-иконки)
- Global hotkey: F19 / CapsLock / Fn как PTT (либо BT-педаль Flic если есть)
- Захват микрофона Mac (AVFoundation / sounddevice)
- POST WAV/Opus на существующий voice-backend
- Playback ответа через system audio out

**Инфра уже готова:**

- voice-backend на VDS
- VK bot bridge, voice-reply wrapper
- Piper TTS
- Whisper / Gemini STT pipeline

**Buy-in:** 1-2 вечера. Если UX норм — идём в железо. Если нет — стоп.

## Future expansion (v0.2+, not blocking v0.1)

- **LoRa Bottom** (M-Bus модуль) — long-range 868 МГц без WiFi, до 10км
- **ESP-MESH** — Wi-Fi mesh network, из коробки на ESP32-S3
- **Starlink** — работает как обычный Wi-Fi AP, ничего не менять
- **USB QWERTY keyboard** — через USB-C OTG cable, ESP32-S3 умеет USB Host
- **Happy coder analog** — tiny text editor + SSH client + 240×320 = 40×20
  chars. Влезает в 8МБ PSRAM, но firmware неделя работы
- **Zigbee/Thread** — S3 не имеет 802.15.4 radio, нужен twin-chip с
  ESP32-H2 через UART bridge
- **GPS/IMU/sensors** — через Grove I2C
- **Slim wearable** — v0.2, кастомная PCB (ESP32-S3 голый + ES8388
  breakout + свой K1 socket на одной плате), 30×40мм вместо 54×54×32мм

## Open questions

- ✅ Модель ESP32-C6 у Sergey дома: **MuseLab NanoESP32-C6 v1.0** (identified 2026-07-08)
- [ ] Baofeng BC-K1 гарнитура для теста концепта за 1.5к vs Vostok HBT-3
  сразу за 8к вслепую — решить после macOS prototype
- [ ] K1 pinout Vostok vs стандарт Baofeng — уточнить у продавца
  (krikam.net / pbsvyaz.ru) перед заказом adapter'а
- [ ] Silence-timer default: 3 сек / 4 сек — тюнинг после dogfood
- [ ] Chord bindings — какие 4-5 нужны кроме hold/click/double/triple

## Refs

- CoreS3 SE docs: https://docs.m5stack.com/en/core/M5CoreS3%20SE
- Module Audio ES8388: https://docs.m5stack.com/en/module/Module-Audio
- Vostok HBT-3 (обзоров нет, только описания): krikam.net, pbsvyaz.ru
- OneButton lib: https://github.com/mathertel/OneButton
- Existing voice-backend: `/root/projects/voice/backend/` (см. CHANGELOG)
- Baofeng UV-5R schematic (K1 pinout auth reference): https://uuki.kapsi.fi/uv5r.html
- Kenwood K1 wiring: https://www.wildtalk.com/knowledge-base/kenwood-2-pin-wiring-data/
- Ham stackexchange K1 pinout: https://ham.stackexchange.com/questions/1891/whats-the-pinout-for-kenwood-2-5mm-trs-3-5-mm-trs-connector

## AliExpress закупка (черновой, 2026-07-13)

Корзина в AliExpress, готова к оплате:

| Позиция | Item ID | Роль |
|---|---|---|
| **3.5mm PJ-392A audio jack** (DQLZV, черный металлический) | 1005005562420070 | Speaker socket в корпусе CoreS3 |
| **2.5mm TRS connector** (NinthQua, для ремонта кабелей — уточнить male/female) | 1005012175823269 | Mic socket в корпусе (нужен FEMALE) |
| **PAM8302A CJMCU-832** audio amplifier | 1005008479519275 | Speaker amp для Mac test + альтернатива CoreS3 |
| **M5Stack ES8388 Audio Module** | 1005008896683697 | CoreS3 mic ADC + electret bias |
| (Item 5 — уточнить) | 1005008262791373 | ? |

**Не в корзине, но нужно докупить:**

- **3.5mm TRRS 4-pole MALE plug разборный** — для DIY mic-adapter iPhone. Поиск: `3.5mm 4 pole TRRS male plug solder`
- **2.5mm TRS FEMALE panel-mount jack PJ-320B** — если item 2 male
- **MAX98357A I2S breakout** — для CoreS3 speaker path (можно PAM8302 обойтись, но MAX98357 через I2S чище архитектурно)
- **10 кΩ резистор 0.25W** — PTT pull-up
- **Тонкий провод 3-4 жилы** — внутренняя разводка

**Финальная сборка (после dogfooding voice-agent-mac):**
- M5Stack CoreS3 SE (Ozon ~5-7к)
- M5Stack Battery Bottom (опц., +1500 мАч) — если 500 мАч не хватит
