import unittest,pathlib,tempfile,os,subprocess,json
ROOT=pathlib.Path(__file__).resolve().parent
class ShortcutTests(unittest.TestCase):
 def call(self,name,args=(),rc=0):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);fake=p/'switch';fake.write_text('#!/usr/bin/env python3\nimport sys,os,json\nopen(os.environ["TRACE"],"w").write(json.dumps(sys.argv[1:]))\nsys.exit(int(os.environ["RESULT"]))\n');fake.chmod(0o755)
   env={**os.environ,'HOME_OS_SWITCH_BIN':str(fake),'TRACE':str(p/'trace'),'RESULT':str(rc)}
   r=subprocess.run(['bash',str(ROOT/name),*args],env=env,capture_output=True,text=True)
   trace=json.loads((p/'trace').read_text()) if (p/'trace').exists() else None
   return r,trace
 def test_plain_commands_only_switch_and_wait(self):
  for name,target in [('winup','windows'),('windown','ubuntu')]:
   with self.subTest(name=name):
    r,trace=self.call(name);self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(trace,[target,'--wait'])
 def test_force_only_when_explicit(self):
  r,trace=self.call('windown',['--force']);self.assertEqual(r.returncode,0);self.assertEqual(trace,['ubuntu','--wait','--force'])
 def test_unknown_argument_does_not_switch(self):
  for arg in ['--with-session','typo']:
   r,trace=self.call('winup',[arg]);self.assertEqual(r.returncode,2);self.assertIsNone(trace)
 def test_preview_and_help_never_switch(self):
  for name in ['winup','windown']:
   for arg in ['--dry-run','--help']:
    r,trace=self.call(name,[arg]);self.assertEqual(r.returncode,0,r.stderr);self.assertIsNone(trace)
 def test_upstream_lease_refusal_is_preserved(self):
  r,trace=self.call('windown',rc=4);self.assertEqual(r.returncode,4)
if __name__=='__main__':unittest.main()
