import json
from pathlib import Path
import tempfile
import unittest

from push import publish_audio


class PushGateTests(unittest.TestCase):
    def test_paused_call_rejects_all_push_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime=Path(directory)
            (runtime/'call-12345678'/'push').mkdir(parents=True)
            (runtime/'active-call.json').write_text(json.dumps({'call_id':'call-12345678','mode':'paused','epoch':2}))
            with self.assertRaises(ValueError):
                publish_audio(runtime,'call-12345678',bytes(320),expected_epoch=2)

    def test_old_epoch_does_not_reappear_after_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime=Path(directory)
            (runtime/'call-12345678'/'push').mkdir(parents=True)
            (runtime/'active-call.json').write_text(json.dumps({'call_id':'call-12345678','mode':'listening','epoch':3}))
            with self.assertRaises(ValueError):
                publish_audio(runtime,'call-12345678',bytes(320),expected_epoch=1)
            path=publish_audio(runtime,'call-12345678',bytes(320),expected_epoch=3)
            self.assertTrue(path.name.startswith('g3-'))


if __name__=='__main__':unittest.main()
