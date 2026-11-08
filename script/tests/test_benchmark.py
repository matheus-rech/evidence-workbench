import importlib.util, pathlib, unittest
SCRIPT=pathlib.Path(__file__).resolve().parents[1]/'evaluate_benchmark.py'
class BenchmarkTests(unittest.TestCase):
    def scorer(self):
        spec=importlib.util.spec_from_file_location('benchmark',SCRIPT);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
    def test_false_support_and_missing_claims_fail_gate(self):
        truth={'claims':[{'id':'right','supported':True,'category':'number'},{'id':'wrong','supported':False,'category':'number'}]}
        bad=self.scorer().score(truth,[{'id':'right','verdict':'supported'},{'id':'wrong','verdict':'supported'}])
        self.assertFalse(bad['gate_passed']);self.assertEqual(bad['false_support_rate'],1);self.assertEqual(bad['true_support_recall'],1)
        missing=self.scorer().score(truth,[{'id':'right','verdict':'supported'}]);self.assertFalse(missing['gate_passed']);self.assertEqual(missing['missing_ids'],['wrong'])
    def test_complete_correct_verdicts_pass_and_duplicates_are_rejected(self):
        truth={'claims':[{'id':'right','supported':True,'category':'number'},{'id':'wrong','supported':False,'category':'group'}]}
        good=self.scorer().score(truth,[{'id':'right','verdict':'supported'},{'id':'wrong','verdict':'contradicted'}]);self.assertTrue(good['gate_passed'])
        with self.assertRaises(ValueError):self.scorer().score(truth,[{'id':'right','verdict':'supported'},{'id':'right','verdict':'supported'}])
if __name__=='__main__':unittest.main()
