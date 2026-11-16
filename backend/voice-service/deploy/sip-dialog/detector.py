"""Lazy per-call Vosk. Importing this module never loads a model."""
import json

from control import normalize


class CommandDetector:
    def __init__(self, model_path, phrases):
        # Intentionally inside construction: there is no process/model without a call.
        import vosk
        vosk.SetLogLevel(-1)
        self._vosk = vosk
        self.model = vosk.Model(str(model_path))
        self.phrases = set(map(normalize, phrases))
        self.recognizer = vosk.KaldiRecognizer(self.model, 16000, json.dumps([*self.phrases, '[unk]'], ensure_ascii=False))
        self._resample_state = None
        self._buffer = bytearray()
        self._hangover = 0
        self._preroll = bytearray()

    def feed(self, pcm):
        # Asterisk AudioSocket supplies 8 kHz PCM. This wideband model expects 16 kHz.
        import audioop
        if audioop.rms(pcm, 2) >= 30:
            self._hangover = 16000  # Two seconds at 8 kHz for final endpointing.
        elif self._hangover <= 0:
            self._preroll.extend(pcm)
            del self._preroll[:-3200]
            return None
        else:
            self._hangover -= len(pcm) // 2
        if self._preroll:
            pcm = bytes(self._preroll) + pcm
            self._preroll.clear()
        converted, self._resample_state = audioop.ratecv(pcm, 2, 1, 8000, 16000, self._resample_state)
        self._buffer.extend(converted)
        if len(self._buffer) < 3200:  # Process at most ten decoder updates / second.
            return None
        data = bytes(self._buffer)
        self._buffer.clear()
        if self.recognizer.AcceptWaveform(data):
            text = normalize(json.loads(self.recognizer.Result()).get('text', ''))
            if text in self.phrases:
                return text
        return None

    def reset(self):
        self.recognizer.Reset()
        self._buffer.clear()
        self._hangover = 0
        self._preroll.clear()
        self._resample_state = None
