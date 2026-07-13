"""
Path A voice agent — Porcupine wake word + OpenAI Realtime API.

Hands-free, streaming, ~500 ms first-response latency. Aimed at racing-wheel
sessions where hands are busy.

Flow:
  wake ("Алёнка") → open Realtime session → mic stream in, audio stream out
  → 8 s of quiet after last response → back to wake listen.
"""

import asyncio
import base64
import json
from pathlib import Path

import numpy as np
import pvporcupine
import sounddevice as sd
from openai import AsyncOpenAI

CONFIG = json.loads(Path("~/.voice-agent-mac/config.json").expanduser().read_text())

MIC_RATE = 24000    # Realtime API PCM16 @ 24 kHz
WAKE_RATE = 16000   # Porcupine PCM16 @ 16 kHz
QUIET_TIMEOUT_S = 8.0


async def _stream_mic(conn, mic_stream):
    """Read mic → append to Realtime input_audio_buffer. Runs until cancelled."""
    loop = asyncio.get_event_loop()
    while True:
        data, _ = await loop.run_in_executor(None, mic_stream.read, 2400)
        await conn.input_audio_buffer.append(audio=base64.b64encode(data.tobytes()).decode())


async def run_conversation():
    """One Realtime session. Returns when quiet timeout hits."""
    client = AsyncOpenAI(api_key=CONFIG["openai_api_key"])
    model = CONFIG.get("realtime_model", "gpt-4o-realtime-preview-2024-12-17")

    playback = sd.OutputStream(samplerate=MIC_RATE, channels=1, dtype="int16")
    playback.start()
    mic_stream = sd.InputStream(samplerate=MIC_RATE, channels=1, dtype="int16", blocksize=2400)
    mic_stream.start()

    print("[Voice] connected — говори…")
    try:
        async with client.beta.realtime.connect(model=model) as conn:
            await conn.session.update(session={
                "modalities": ["audio", "text"],
                "voice": CONFIG.get("voice", "verse"),
                "instructions": CONFIG.get("system_prompt",
                    "Ты голосовой ассистент. Отвечай кратко, разговорно, по-русски. "
                    "Максимум 2-3 предложения если сам не решил иначе."),
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": {"model": "whisper-1"},
                "turn_detection": {
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 700,
                },
            })

            mic_task = asyncio.create_task(_stream_mic(conn, mic_stream))
            last_activity = asyncio.get_event_loop().time()

            async for event in conn:
                t = event.type

                if t == "response.audio.delta":
                    audio = np.frombuffer(base64.b64decode(event.delta), dtype="int16")
                    playback.write(audio.reshape(-1, 1))

                elif t == "conversation.item.input_audio_transcription.completed":
                    print(f"[You]: {event.transcript}")
                    last_activity = asyncio.get_event_loop().time()

                elif t == "response.done":
                    try:
                        text = event.response.output[0].content[0].transcript
                        print(f"[Assistant]: {text}")
                    except (IndexError, AttributeError, KeyError):
                        pass
                    last_activity = asyncio.get_event_loop().time()

                elif t == "input_audio_buffer.speech_started":
                    last_activity = asyncio.get_event_loop().time()

                elif t == "error":
                    print(f"[ERROR]: {event}")
                    break

                if asyncio.get_event_loop().time() - last_activity > QUIET_TIMEOUT_S:
                    print("[Voice] quiet, back to wake word…")
                    break

            mic_task.cancel()
    finally:
        mic_stream.stop(); mic_stream.close()
        playback.stop(); playback.close()


def wake_loop():
    """Blocking wake word loop; opens Realtime session on detection."""
    porcupine = pvporcupine.create(
        access_key=CONFIG["porcupine_access_key"],
        keyword_paths=[CONFIG["porcupine_keyword_path"]],
    )
    keyword = Path(CONFIG["porcupine_keyword_path"]).stem
    print(f"[Wake] Listening for «{keyword}»…")
    try:
        while True:
            stream = sd.InputStream(samplerate=WAKE_RATE, channels=1, dtype="int16",
                                    blocksize=porcupine.frame_length)
            stream.start()
            try:
                while True:
                    frame, _ = stream.read(porcupine.frame_length)
                    if porcupine.process(frame.flatten()) >= 0:
                        print(f"[Wake] «{keyword}» detected!")
                        break
            finally:
                stream.stop(); stream.close()

            asyncio.run(run_conversation())
            print(f"[Wake] Listening for «{keyword}»…")
    finally:
        porcupine.delete()


if __name__ == "__main__":
    try:
        wake_loop()
    except KeyboardInterrupt:
        print("\nBye.")
