import importlib.util,pathlib,unittest
PATH=pathlib.Path(__file__).resolve().parents[2]/'benchmarks/ocr-pilot/serve_paddle.py'
spec=importlib.util.spec_from_file_location('paddleservice',PATH);service=importlib.util.module_from_spec(spec);spec.loader.exec_module(service)
class PaddleServiceAccessTests(unittest.TestCase):
 def test_only_authenticated_non_browser_json_is_accepted(self):
  token='synthetic-test-token-with-32-characters'
  valid={'Content-Type':'application/json','Authorization':'Bearer '+token}
  self.assertTrue(service.authorized(valid,token))
  for extra in [{'Origin':'https://example.com'},{'Origin':'null'},{'Content-Type':'text/plain'},{'Authorization':'Bearer wrong'}]:
   self.assertFalse(service.authorized(dict(valid,**extra),token))
  self.assertFalse(service.authorized(valid,''))
if __name__=='__main__':unittest.main()
