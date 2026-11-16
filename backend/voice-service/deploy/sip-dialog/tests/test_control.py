import unittest

from control import VoiceControl, tone


SPEECH = b'\x00\x10' * 160
SILENCE = bytes(320)


class VoiceControlTests(unittest.TestCase):
    def drain(self, control):
        while control.playing:
            control.output_frame()

    def test_paused_ordinary_speech_never_becomes_a_request(self):
        c = VoiceControl()
        for _ in range(800):
            self.assertIsNone(c.receive(SPEECH))
        self.assertEqual(c.mode, 'paused')
        self.assertEqual(c.captured_bytes, 0)

    def test_command_punctuation_is_not_part_of_the_phrase(self):
        c=VoiceControl()
        c.command('Голосовой помощник, слушай!')
        self.assertEqual(c.mode,'ready')

    def test_start_cue_finishes_before_capture_begins(self):
        c = VoiceControl()
        c.command(c.start_phrase)
        self.assertEqual(c.mode, 'ready')
        self.assertIsNone(c.receive(SPEECH))
        self.assertEqual(c.captured_bytes, 0)
        self.drain(c)
        self.assertEqual(c.mode, 'listening')
        c.receive(SPEECH)
        self.assertGreater(c.captured_bytes, 0)

    def test_exact_stop_interrupts_playback_and_rejects_old_result(self):
        c = VoiceControl()
        c.command(c.start_phrase)
        self.drain(c)
        epoch = c.epoch
        self.assertTrue(c.result(epoch, b'O' + SPEECH * 400))
        self.assertEqual(c.mode, 'speaking')
        c.command(c.stop_phrase)
        self.assertEqual(c.mode, 'paused')
        self.drain(c)
        self.assertEqual(c.output_frame(), SILENCE)
        self.assertFalse(c.result(epoch, b'O' + SPEECH * 400))

    def test_quoted_or_partial_command_does_not_change_mode(self):
        c = VoiceControl()
        for words in ['стоп', 'пауза', 'голосовой помощник', 'он сказал голосовой помощник слушай']:
            c.command(words)
            self.assertEqual(c.mode, 'paused')

    def test_complete_speech_is_submitted_once_after_silence(self):
        c = VoiceControl()
        c.command(c.start_phrase)
        self.drain(c)
        for _ in range(50):
            self.assertIsNone(c.receive(SPEECH))
        jobs = [c.receive(SILENCE) for _ in range(151)]
        jobs = [j for j in jobs if j is not None]
        self.assertEqual(len(jobs), 1)
        self.assertEqual(jobs[0][0], c.epoch)
        self.assertTrue(jobs[0][1].startswith(SPEECH))
        self.assertEqual(c.mode, 'thinking')

    def test_stop_discards_recording_and_delayed_push(self):
        c = VoiceControl()
        c.command(c.start_phrase)
        self.drain(c)
        c.receive(SPEECH)
        epoch = c.epoch
        c.command(c.stop_phrase)
        self.assertEqual(c.captured_bytes, 0)
        self.assertFalse(c.push(epoch, SPEECH*10))

    def test_heartbeat_is_quiet_rare_and_does_not_change_mode(self):
        c = VoiceControl(heartbeat_seconds=30)
        self.assertFalse(c.heartbeat(29))
        self.assertTrue(c.heartbeat(30))
        self.assertEqual(c.mode, 'paused')
        self.drain(c)
        self.assertFalse(c.heartbeat(31))


if __name__ == '__main__':
    unittest.main()
