import unittest,tempfile,pathlib,os,subprocess,json
LIB=str(pathlib.Path(__file__).resolve().parent/'lib_inject.sh')
class InjectionTests(unittest.TestCase):
 def run_case(self,native=True,mismatch=False,sid='happy-exact'):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);fake=p/'node';fake.write_text('''#!/usr/bin/env python3
import sys,os,json,pathlib
with open(os.environ['CALLS'],'a') as f:f.write(json.dumps(sys.argv[1:])+"\\n")
if '--input-type=module' in sys.argv:
 sys.stdin.read();sys.exit(int(os.environ.get('IDENTITY_FAIL','0')))
''');fake.chmod(0o755)
   env={**os.environ,'PATH':d+':'+os.environ['PATH'],'CALLS':str(p/'calls'),'IDENTITY_FAIL':'1' if mismatch else '0','VOICE_NATIVE_ID':'native-exact' if native else '','INJECT_SID':sid,'INJECT_CWD':'/root/projects/voice','INJECT':'/existing/inject.mjs','PAYLOAD':'quoted \' text $(touch /never-run)\nsecond line'}
   r=subprocess.run(['bash','-c','source "$1"; inject_to "$PAYLOAD"','test',LIB],env=env,capture_output=True,text=True)
   calls=[json.loads(x) for x in (p/'calls').read_text().splitlines()] if (p/'calls').exists() else []
   return r,calls,env['PAYLOAD']
 def test_native_checks_identity_then_sends_exact_payload(self):
  r,calls,text=self.run_case();self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(len(calls),2)
  self.assertIn('--strict-sid',calls[1]);self.assertEqual(calls[1][calls[1].index('--native-id')+1],'native-exact');self.assertEqual(calls[1][-1],text)
 def test_mismatch_never_sends(self):
  r,calls,_=self.run_case(mismatch=True);self.assertNotEqual(r.returncode,0);self.assertEqual(len(calls),1)
 def test_native_requires_exact_happy_sid(self):
  r,calls,_=self.run_case(sid='');self.assertEqual(r.returncode,2);self.assertEqual(calls,[])
 def test_legacy_still_sends_without_native_reader(self):
  r,calls,text=self.run_case(native=False);self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(len(calls),1);self.assertNotIn('--native-id',calls[0]);self.assertEqual(calls[0][-1],text)
if __name__=='__main__':unittest.main()
