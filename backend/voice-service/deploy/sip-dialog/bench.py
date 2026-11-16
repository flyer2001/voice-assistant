#!/usr/bin/python3
"""Bounded, paced AudioSocket benchmark. Uses real Vosk and a fake agent boundary."""
import argparse
from array import array
import json
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import uuid

from worker import Frames


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--mode', choices=['paused','dialog'], required=True)
    parser.add_argument('--seconds', type=int, default=25)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assets = args.assets
    fixture = lambda name: (assets/'control-fixtures'/f'{name}.sln').read_bytes()
    stream = bytearray(args.seconds * 16000)
    if args.mode == 'dialog':
        for at, name in [(1,'start'),(6,'negative'),(17,'stop')]:
            pcm=fixture(name)
            stream[at*16000:at*16000+len(pcm)] = pcm
    with tempfile.TemporaryDirectory(prefix='control-bench-') as folder:
        root = Path(folder)
        (root/'push').mkdir()
        nonce = uuid.uuid4()
        bridge_path = root/'bridge.sock'
        requests = []
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(str(bridge_path));listener.listen(2);listener.settimeout(1)
        stopped = threading.Event()

        def agent():
            while not stopped.is_set():
                try:client,_=listener.accept()
                except socket.timeout:continue
                with client:
                    data=bytearray()
                    while chunk:=client.recv(65536):data.extend(chunk)
                    requests.append(len(data))
                    client.sendall(b'O'+fixture('reply'))

        thread=threading.Thread(target=agent,daemon=True);thread.start()
        command=[sys.executable,str(Path(__file__).with_name('worker.py')),
                 '--parent-pid',str(os.getpid()),
                 '--root',str(root),'--model',str(assets/'vosk-model-small-ru-0.22'),
                 '--uuid',str(nonce),'--bridge',str(bridge_path),'--heartbeat','8']
        with (root/'stderr.log').open('w') as log:
            process=subprocess.Popen(command,stdout=subprocess.DEVNULL,stderr=log)
            try:
                deadline=time.monotonic()+20
                while not (root/'control-ready.json').exists():
                    if process.poll() is not None:raise RuntimeError((root/'stderr.log').read_text())
                    if time.monotonic()>deadline:raise TimeoutError('model load')
                    time.sleep(.02)
                ready=json.loads((root/'control-ready.json').read_text())
                decoded=bytearray();decoder=Frames()
                with socket.create_connection(('127.0.0.1',ready['port'])) as client:
                    client.sendall(struct.pack('!BH',1,16)+nonce.bytes)
                    start=time.monotonic();offset=0
                    while offset<len(stream):
                        due=start+offset/16000
                        wait=max(0,due-time.monotonic())
                        readable,_,_=select.select([client],[],[],min(.02,wait))
                        if readable:
                            raw=client.recv(8192)
                            if not raw:break
                            for kind,pcm in decoder.feed(raw):
                                if kind==0x10:decoded.extend(pcm)
                        if time.monotonic()>=due:
                            frame=stream[offset:offset+320]
                            client.sendall(struct.pack('!BH',0x10,len(frame))+frame)
                            offset+=len(frame)
                    client.sendall(b'\0\0\0')
                process.wait(timeout=5)
                result=json.loads((root/'control-metrics.json').read_text())
                result.update(mode=args.mode,requests=requests,
                              output_seconds=len(decoded)/16000,
                              worker_exited=not Path(f'/proc/{process.pid}').exists())
                result['cpu_percent_one_core']=round(100*result['run_cpu_s']/result['run_wall_s'],2)
                if args.mode=='paused':
                    assert not requests,result
                    assert not result['counts'].get('starts'),result
                else:
                    assert result['counts'].get('starts')==1,result
                    assert result['counts'].get('stops')==1,result
                    assert len(requests)==1,result
                    stop=next(e['at_s'] for e in result['command_events'] if e['action']=='stop')
                    command_end=17+len(fixture('stop'))/16000
                    result['stop_after_phrase_end_s']=round(stop-command_end,3)
                    assert 0 <= result['stop_after_phrase_end_s'] < 1.5,result
                    tail=array('h',decoded[int((stop+.3)*16000):int((stop+1.0)*16000)])
                    assert tail and max(map(abs,tail)) < 50,'Output continued after stop'
                assert result['worker_exited'],result
                args.out.write_text(json.dumps(result,indent=2)+'\n')
                print(json.dumps(result))
            finally:
                if process.poll() is None:process.terminate();process.wait(timeout=5)
                stopped.set();listener.close()


if __name__=='__main__':main()
