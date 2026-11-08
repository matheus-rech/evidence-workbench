# Source-check regression benchmark

Twenty frozen claims: twelve hand-checked Table 1 cells from the existing Arts pilot and eight negative/error categories. These are a small regression corpus, not an independently adjudicated empirical accuracy study. A second independent reviewer and a held-out corpus are still required for that claim. Gold labels and their source references are reviewable in `source-check-claims.json`.

Record predictions as a JSON array of `{ "id": "...", "verdict": "supported|contradicted|unclear" }`. Score an actual checker run with:

```
python3 script/evaluate_benchmark.py --truth benchmarks/source-check-claims.json --predictions your-run.json --output benchmark-report.json
```

The gate exits 2 for incomplete coverage, any false support, or a missed positive. Exact values/group/time/statistic are encoded in individual positive claim IDs; negatives address wrong digit, group, time, unit, denominator, statistic and silent derivation. Metrics on incomplete runs are explicitly conditional on observed predictions. Duplicate/unknown IDs fail.

`observed-historical-false-support.json` is the one actually observed negative verdict preserved in the prior audit, not a fabricated new run. It must fail this gate. Do not fill the remaining predictions with expected labels and call that a measured model score. Unit tests use fabricated verdicts only to test the scorer's failure behavior. New model calls are not performed by this tool and credentials are never read.

Automatic mode is guarded independently: wrong/unanchored 9292 and a correctly quoted 8292 used to support value 9292 both remain unresolved. Other semantic errors can still survive model review; exports label AI decisions explicitly and include unresolved observations.
