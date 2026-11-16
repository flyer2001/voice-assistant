import sys
import types
import unittest
from unittest.mock import patch

from detector import CommandDetector


class DetectorTests(unittest.TestCase):
    def make(self):
        calls = []
        recognizer = types.SimpleNamespace(
            AcceptWaveform=lambda pcm:calls.append(pcm) or False,
            Reset=lambda:None,
        )
        module = types.SimpleNamespace(SetLogLevel=lambda n:None,Model=lambda p:object(),KaldiRecognizer=lambda *a:recognizer)
        with patch.dict(sys.modules,vosk=module):
            detector=CommandDetector('/fixture',['голосовой помощник слушай'])
        return detector,calls

    def test_long_silence_does_not_invoke_decoder(self):
        detector,calls=self.make()
        for _ in range(500):detector.feed(bytes(320))
        self.assertEqual(calls,[])

    def test_trailing_silence_still_reaches_decoder_to_finish_phrase(self):
        detector,calls=self.make()
        for _ in range(10):detector.feed(b'\x00\x10'*160)
        before=len(calls)
        for _ in range(50):detector.feed(bytes(320))
        self.assertGreater(len(calls),before)


if __name__=='__main__':unittest.main()
