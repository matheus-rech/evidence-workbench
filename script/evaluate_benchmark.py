#!/usr/bin/env python3
"""Score frozen, source-adjudicated claims. No API calls; missing coverage fails the gate."""
import argparse, json
from pathlib import Path

def score(truth, predictions):
    claims=truth['claims']; expected={c['id']:c for c in claims}
    if len(expected)!=len(claims):raise ValueError('Duplicate truth IDs')
    seen={}
    for row in predictions:
        if row['id'] not in expected or row['id'] in seen:raise ValueError('Unknown or repeated prediction ID')
        if row['verdict'] not in {'supported','contradicted','unclear'}:raise ValueError('Invalid verdict')
        seen[row['id']]=row
    negatives=[i for i in seen if not expected[i]['supported']]
    positives=[i for i in seen if expected[i]['supported']]
    fp=[i for i in negatives if seen[i]['verdict']=='supported']
    tp=[i for i in positives if seen[i]['verdict']=='supported']
    missed=sorted(set(expected)-set(seen))
    fpr=len(fp)/len(negatives) if negatives else None
    recall=len(tp)/len(positives) if positives else None
    return {'expected_claims':len(expected),'observed_claims':len(seen),'missing_ids':missed,'false_support_ids':fp,'false_support_rate':fpr,'true_support_recall':recall,'negative_claims_observed':len(negatives),'positive_claims_observed':len(positives),'by_category':{category:{'observed':sum(expected[i]['category']==category for i in seen),'false_support':sum(expected[i]['category']==category for i in fp)} for category in sorted({c['category'] for c in claims})},'gate_passed':not missed and fpr==0 and recall==1,'interpretation':'Small regression gate only; no population accuracy or independence claim.'}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--truth',type=Path,required=True);parser.add_argument('--predictions',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    report=score(json.loads(args.truth.read_text()),json.loads(args.predictions.read_text()));args.output.write_text(json.dumps(report,indent=2)+'\n');raise SystemExit(0 if report['gate_passed'] else 2)
if __name__=='__main__':main()
