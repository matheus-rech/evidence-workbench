import re,json,collections,statistics,argparse
from decimal import Decimal
from html.parser import HTMLParser
from pathlib import Path

def numeric(text):
 # Numeric values, not typography: thousands separators and trailing decimal zeros are equivalent.
 raw=re.findall(r'(?<![\d.])\d+(?:,\d{3})*(?:\.\d+)?(?![\d.])',text)
 return [str(Decimal(n.replace(',','')).normalize()) for n in raw]
def cell_signature(text):
 text=re.sub(r'<[^>]*>',' ',text).replace('\\pm','±')
 return (numeric(text), '±' in text, text.count('%'), text.lower().count('ci'), bool(re.search(r'n\s*/\s*a',text,re.I)), not text.strip())
class Tables(HTMLParser):
 def __init__(self):super().__init__();self.tables=[];self.table=None;self.row=None;self.cell=None
 def handle_starttag(self,tag,attrs):
  if tag=='table':self.table=[]
  elif tag=='tr' and self.table is not None:self.row=[]
  elif tag in ('td','th') and self.row is not None:self.cell=''
 def handle_data(self,data):
  if self.cell is not None:self.cell+=data
 def handle_endtag(self,tag):
  if tag in ('td','th') and self.cell is not None:self.row.append(self.cell);self.cell=None
  elif tag=='tr' and self.row is not None:self.table.append(self.row);self.row=None
  elif tag=='table' and self.table is not None:self.tables.append(self.table);self.table=None

def grids(text):
 if '<fcel>' in text:
  rows=[];row=[]
  for part in re.split(r'(<(?:fcel|ecel|lcel|ucel|xcel|nl)>)',text):
   if part=='<nl>':
    if row:rows.append(row)
    row=[]
   elif part in ('<fcel>','<ecel>'):row.append('')
   elif part=='<lcel>':row.append(row[-1] if row else '')
   elif part in ('<ucel>','<xcel>'):row.append(rows[-1][len(row)] if rows and len(rows[-1])>len(row) else '')
   elif row:row[-1]+=part
  if row:rows.append(row)
  return [rows]
 p=Tables();p.feed(text)
 if p.tables:return p.tables
 rows=[]
 for line in text.splitlines():
  if line.count('|')>=2 and not re.fullmatch(r'[\s|:\-]+',line):rows.append([c.strip() for c in line.strip().strip('|').split('|')])
 return [rows] if rows else []

def table_score(text,gold):
 expected=collections.Counter(n for row in gold for cell in row[1:] for n in numeric(cell))
 found=collections.Counter(numeric(text));recall=sum((expected&found).values())/sum(expected.values())
 # Body-row matching by normalized source label; no guessed column shifts or dropped empty cells.
 def label(t):return re.sub(r'[^a-z0-9]','',t.lower().replace('\\geq','≥').replace('\\leq','≤'))
 parsed=grids(text);correct=0;total=sum(len(row)-1 for row in gold)
 for row in gold:
  candidates=[p for table in parsed for p in table if p and label(p[0])==label(row[0])]
  if len(candidates)==1 and len(candidates[0])==len(row):
   correct+=sum(cell_signature(a)==cell_signature(b) for a,b in zip(row[1:],candidates[0][1:]))
 return {'body_numeric_tokens':sum(expected.values()),'body_numeric_recall':recall,'grid_cells_correct':correct,'grid_cells_total':total,'numeric_cell_association_accuracy':correct/total if parsed else None,'structured_grid_produced':bool(parsed)}

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--results-dir',type=Path,default=Path(__file__).resolve().parents[1]/'benchmarks'/'ocr-pilot');root=parser.parse_args().results_dir;gold=json.loads((root/'gold-source-transcription.json').read_text());records=json.loads((root/'apple-vision.json').read_text())
 if (root/'remote-results.json').exists():records+=json.loads((root/'remote-results.json').read_text())
 scores=[]
 for r in records:
  result={k:v for k,v in r.items() if k not in ['text','lines']}
  if r['sample'] in gold['tables']:result.update(table_score(r.get('text',''),gold['tables'][r['sample']]['rows']))
  elif r['sample']+'-table' in gold['tables']:
   result['full_page_table_numeric_recall']=table_score(r.get('text',''),gold['tables'][r['sample']+'-table']['rows'])['body_numeric_recall']
  if r['sample'] in gold['figure_checks']:
   expected=gold['figure_checks'][r['sample']];found=collections.Counter(numeric(r.get('text','')))
   result['figure_numeric_matches']=sum(found[str(Decimal(n).normalize())]>0 for n in expected);result['figure_numeric_total']=len(expected)
  scores.append(result)
 (root/'scores.json').write_text(json.dumps(scores,indent=2))
 summary={}
 for engine in sorted({r['engine'] for r in scores}):
  rs=[r for r in scores if r['engine']==engine];ts=[r for r in rs if 'grid_cells_total' in r];errors=[r for r in rs if r.get('error')]
  summary[engine]={'observations':len(rs),'failures':len(errors),'token_cap_hits':sum(bool(r.get('hit_token_cap')) for r in rs),'median_seconds':statistics.median(r['elapsed_seconds'] for r in rs),'maximum_process_peak_rss_bytes':max(r.get('process_peak_rss_bytes',0) for r in rs),'maximum_gpu_peak_allocated_bytes':max((r['gpu_peak_allocated_bytes'] for r in rs if 'gpu_peak_allocated_bytes' in r),default=None),'numeric_body_recall_by_table':{s:statistics.mean(r['body_numeric_recall'] for r in ts if r['sample']==s) for s in sorted({r['sample'] for r in ts})},'numeric_cell_association_by_table':{s:statistics.mean(r['numeric_cell_association_accuracy'] for r in ts if r['sample']==s and r['numeric_cell_association_accuracy'] is not None) if any(r['sample']==s and r['numeric_cell_association_accuracy'] is not None for r in ts) else None for s in sorted({r['sample'] for r in ts})}}
 (root/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
if __name__=='__main__':main()
