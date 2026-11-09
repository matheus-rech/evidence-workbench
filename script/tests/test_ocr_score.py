import importlib.util,pathlib,unittest
PATH=pathlib.Path(__file__).resolve().parents[1]/'score_ocr_pilot.py'
spec=importlib.util.spec_from_file_location('ocrscore',PATH);score=importlib.util.module_from_spec(spec);spec.loader.exec_module(score)
class OCRScoringTests(unittest.TestCase):
 def test_numeric_units_and_missing_values_are_not_equivalent(self):
  self.assertNotEqual(score.cell_signature('n/a'),score.cell_signature(''))
  self.assertNotEqual(score.cell_signature('10,570 ± 5,032'),score.cell_signature('10,570 - 5,032'))
  self.assertNotEqual(score.cell_signature('73%'),score.cell_signature('73'))
  self.assertEqual(score.cell_signature('70.0 (95% CI 62.9–77.7)'),score.cell_signature('70 (95%CI62.9-77.7)'))
 def test_grid_positions_not_just_bag_of_numbers(self):
  gold=[['N','235','496'],['Mean','74.61','72.13']]
  shifted='<table><tr><td>N</td><td>496</td><td>235</td></tr><tr><td>Mean</td><td>72.13</td><td>74.61</td></tr></table>'
  result=score.table_score(shifted,gold);self.assertEqual(result['body_numeric_recall'],1);self.assertEqual(result['numeric_cell_association_accuracy'],0)
 def test_otsl_blank_cells_preserve_column_association(self):
  result=score.table_score('<fcel>N<fcel>235<ecel><fcel>496<nl>',[['N','235','','496']]);self.assertEqual(result['numeric_cell_association_accuracy'],1)
if __name__=='__main__':unittest.main()
