import struct
import os
import select
import subprocess
import sys
import unittest
from pathlib import Path

from worker import Frames


class WireTests(unittest.TestCase):
    def test_fragmented_header_and_payload_preserve_frames(self):
        data = struct.pack('!BH', 1, 16) + bytes(16) + struct.pack('!BH', 0x10, 320) + bytes(320)
        parser = Frames()
        frames = []
        for byte in data:
            frames += parser.feed(bytes([byte]))
        self.assertEqual(frames, [(1,bytes(16)),(0x10,bytes(320))])

    def test_invalid_pcm_is_rejected(self):
        with self.assertRaises(ValueError):
            Frames().feed(struct.pack('!BH',0x10,1)+b'x')

    def test_no_agi_call_does_not_start_a_worker(self):
        launch = Path(__file__).resolve().parents[1]/'launch.py'
        result = subprocess.run([sys.executable,str(launch)],input='',text=True,capture_output=True,timeout=5)
        self.assertEqual(result.returncode,2)
        self.assertEqual(result.stdout,'')

    def test_hard_killed_call_owner_cannot_leave_child_running(self):
        module=str(Path(__file__).resolve().parents[1])
        child_code='import os,signal; from worker import bind_to_parent; bind_to_parent(int(__import__("sys").argv[1])); print("ready",flush=True); signal.pause()'
        parent_code='import os,signal,subprocess,sys; p=subprocess.Popen([sys.executable,"-c",sys.argv[1],str(os.getpid())],stdout=subprocess.PIPE,text=True); assert p.stdout.readline().strip()=="ready"; print(p.pid,flush=True); signal.pause()'
        parent=subprocess.Popen([sys.executable,'-c',parent_code,child_code],env=dict(os.environ,PYTHONPATH=module),stdout=subprocess.PIPE,text=True)
        fd=None
        try:
            child_pid=int(parent.stdout.readline())
            fd=os.pidfd_open(child_pid)
            parent.kill();parent.wait(timeout=3)
            poll=select.poll();poll.register(fd,select.POLLIN)
            self.assertTrue(poll.poll(3000),'Child survived the call owner')
        finally:
            if parent.poll() is None:parent.kill();parent.wait()
            if fd is not None:os.close(fd)
            parent.stdout.close()


if __name__ == '__main__':
    unittest.main()
