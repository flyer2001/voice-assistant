# iPhone bench — status checkpoint (2026-06-10 night)

## Where we are

- ✅ App skeleton развёрнута на iPhone 13 mini (iOS 26.5), UI работает, Speech framework reachable
- ✅ Personal Team signing настроен (Apple ID `flyer2001@isnet.ru`, Team `V729HQ39RD`, Bundle ID `com.voiceassistant.app.flyer2001`)
- ✅ XcodeGen project gen + xcodebuild SSH build chain работает
- ✅ V1 BenchRunner написан: autostart on launch, 3 Apple STT candidates (SFSpeechRecognizer + DictationTranscriber + SpeechTranscriber), CSV output в Documents, os_log progress
- ✅ 32 audio файла копируются в bundle через `iOS/setup-resources.sh`

## Blocker on 2026-06-10 23:50

Утром после `killall -9 Xcode` (нужен был для clean SSH device session) **Apple ID account в Xcode preferences не сохранился**. Последующий SSH build выдаёт:

```
error: No Accounts: Add a new account in Accounts settings.
error: No profiles for 'com.voiceassistant.app.flyer2001' were found
```

`~/Library/MobileDevice/Provisioning Profiles/` пуст — Xcode GUI build на iPhone не делался (только simulator/SPM builds).

## Утром — что Sergey делает

Через VNC (или открыть крышку):

1. **Открыть Xcode → Settings (⌘,) → Accounts** — проверить что `flyer2001@isnet.ru` присутствует
   - Если нет → `+` → Apple ID → войти заново с 2FA
2. **Открыть** `~/projects/voice-assistant/iOS/VoiceAssistantApp.xcodeproj`
3. **Выбрать iPhone 13 mini** в destination dropdown
4. **▶ Run** (⌘R) — Xcode сам:
   - создаст provisioning profile в `~/Library/MobileDevice/Provisioning Profiles/`
   - подпишет
   - установит app на iPhone
   - запустит
5. App при запуске **autostart bench** (благодаря ContentView.onAppear → BenchRunner.runAll())
6. После того как Xcode build succeeded — **закрыть Xcode чистым Quit (⌘Q)**, НЕ через kill — preferences сохранятся
7. Сказать мне — я ssh retry, дальше всё headless

## После того как профиль есть

VDS Claude session делает (один SSH command):

```bash
ssh mac-home '
  cd ~/projects/voice-assistant/iOS
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodebuild -project VoiceAssistantApp.xcodeproj \
    -scheme VoiceAssistantApp \
    -destination "platform=iOS,id=00008110-000A024A0E78801E" \
    -configuration Debug -derivedDataPath /tmp/xcb-device \
    -allowProvisioningUpdates build
  xcrun devicectl device install app \
    --device 0435DD81-0F8C-59BA-A3D3-914358AB2423 \
    /tmp/xcb-device/Build/Products/Debug-iphoneos/VoiceAssistantApp.app
  xcrun devicectl device process launch \
    --device 0435DD81-0F8C-59BA-A3D3-914358AB2423 \
    --terminate-existing \
    com.voiceassistant.app.flyer2001
'
```

Затем ждать 5-15 минут пока bench runs (3 модели × 32 файла × 3 повтора = 288 transcriptions), потом pull CSV:

```bash
ssh mac-home 'xcrun devicectl device copy from --device 0435DD81-0F8C-59BA-A3D3-914358AB2423 \
  --source /Documents/bench-results.csv \
  --destination ~/ai-bench/ios-bench-results.csv'
scp mac-home:~/ai-bench/ios-bench-results.csv /root/projects/voice/bench/results/
/root/projects/voice/bench/.venv/bin/python bench/scripts/compute_metrics.py \
  --input bench/results/ios-bench-results.csv \
  --output bench/results/ios-bench-metrics.csv
```

## Что VDS Claude session делает ночью без блокера

- ✅ Simulator build в background (verify SpeechTranscriber API правильный)
- Возможно — pre-download WhisperKit Core ML models через VDS proxy для V2

## Гипотезы по результатам V1 (Apple-only)

- **SpeechTranscriber** на коротких dev-командах должен быть лучше SFSpeechRecognizer на term accuracy (англицизмы) — Apple's new model trained on long-form, distant audio
- **DictationTranscriber** — fallback с тем же engine что keyboard dictation, может быть слабее на russifications англицизмов
- **SFSpeechRecognizer** baseline — legacy, но проверенный для русского

Если **SpeechTranscriber WER < 10%** на наших командах — это **default для v0.1 voice assistant**. Никаких WhisperKit, никаких model downloads, всё бесплатно из коробки.

V2 с WhisperKit base/small покажет — стоит ли overhead 480MB модели + первый-cold load для marginal улучшения качества.

## Ссылки

- HYP-028 (myRep/_project-hub) — родительский benchmark plan
- HYP-045 — voice IVR через GSM, ΔWER GSM ответит на feasibility
- `docs/whisper-benchmark-plan.md` — voice-локальный план
- `bench/IOS_BENCH_BRIEF.md` — instructions если переходим на отдельную mac-home Claude session
