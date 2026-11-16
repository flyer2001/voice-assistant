"""Per-call voice states. No models, processes, networking, or clocks at import."""
from array import array
import math
import re

RATE = 8000
FRAME_BYTES = 320
SILENCE = bytes(FRAME_BYTES)


def tone(hz=700, seconds=0.12, level=3500):
    count = int(RATE * seconds)
    samples = array('h')
    for i in range(count):
        edge = min(1.0, i / 80, (count - i - 1) / 80)
        samples.append(int(level * edge * math.sin(2 * math.pi * hz * i / RATE)))
    return samples.tobytes()


def normalize(text):
    return ' '.join(re.sub(r'[.,!?:;]', ' ', text.lower().replace('ё','е')).split())


class VoiceControl:
    def __init__(self, *, start_phrase='голосовой помощник слушай',
                 stop_phrase='голосовой помощник пауза', heartbeat_seconds=45):
        self.start_phrase, self.stop_phrase = normalize(start_phrase), normalize(stop_phrase)
        self.mode = 'paused'
        self.epoch = 0
        self._capture = bytearray()
        self._silent_bytes = 0
        self._audio = b''
        self._offset = 0
        self._label = ''
        self.last_finished = ''
        self.heartbeat_seconds = heartbeat_seconds
        self._heartbeat_at = 0.0
        self._warning = False

    @property
    def captured_bytes(self):
        return len(self._capture)

    @property
    def playing(self):
        return self._offset < len(self._audio)

    def _play(self, audio, label):
        self._audio, self._offset, self._label = audio, 0, label

    def _clear_capture(self):
        self._capture.clear()
        self._silent_bytes = 0
        self._warning = False

    def connected(self):
        self._play(tone(500, .08, 900), 'connected')

    def command(self, text):
        words = normalize(text)
        if words == self.stop_phrase and self.mode != 'paused':
            self.epoch += 1
            self.mode = 'paused'
            self._clear_capture()
            self._play(tone(450, .08, 1800), 'paused')
            return 'stop'
        if words == self.start_phrase and self.mode == 'paused':
            self.epoch += 1
            self._clear_capture()
            self.mode = 'ready'
            self._play(tone(900, .18, 3500), 'ready')
            return 'start'
        return None

    def receive(self, pcm):
        if self.mode != 'listening' or not pcm:
            return None
        loud = max(map(abs, array('h', pcm))) >= 180
        if not self._capture and not loud:
            return None
        self._capture.extend(pcm)
        self._silent_bytes = 0 if loud else self._silent_bytes + len(pcm)
        # Existing bounded trial contract: 120 s, warning at 110 s, 3 s silence.
        if len(self._capture) >= 110 * RATE * 2 and not self._warning:
            self._play(tone(1000, .18, 3500), 'warning')
            self._warning = True
        if self._silent_bytes >= 3 * RATE * 2 or len(self._capture) >= 120 * RATE * 2:
            return self.submit()
        return None

    def submit(self):
        if self.mode != 'listening' or not self._capture:
            return None
        audio = bytes(self._capture)
        self._clear_capture()
        self.mode = 'thinking'
        self._play(tone(600, .06, 1800), 'submitted')
        return self.epoch, audio

    def result(self, epoch, response):
        if epoch != self.epoch or self.mode == 'paused':
            return False
        if response[:1] == b'O' and 100 < len(response) <= 960001:
            self.mode = 'speaking'
            self._play(response[1:], 'reply')
        elif response[:1] == b'Q':
            self.mode = 'listening'
        else:
            self.mode = 'listening'
            self._play(tone(300, .12, 2000), 'unavailable')
        return True

    def push(self, epoch, pcm):
        if epoch != self.epoch or self.mode != 'listening' or self._capture or self.playing:
            return False
        self.mode = 'speaking'
        self._play(pcm, 'push')
        return True

    def heartbeat(self, now):
        if not self.heartbeat_seconds or self.mode not in ('paused', 'listening'):
            return False
        if self.playing or self._capture or now - self._heartbeat_at < self.heartbeat_seconds:
            return False
        self._heartbeat_at = now
        self._play(tone(500, .06, 250), 'heartbeat')
        return True

    def output_frame(self):
        self.last_finished = ''
        if not self.playing:
            return SILENCE
        frame = self._audio[self._offset:self._offset + FRAME_BYTES]
        self._offset += len(frame)
        if not self.playing:
            label = self._label
            self._audio, self._offset, self._label = b'', 0, ''
            self.last_finished = label
            if label in ('ready', 'reply', 'push') and self.mode != 'paused':
                self.mode = 'listening'
        return frame.ljust(FRAME_BYTES, b'\0')
