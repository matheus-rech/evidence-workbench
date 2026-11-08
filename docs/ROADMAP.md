# Development backlog

This is an assisted extraction preview, not a hallucination-proof or scientifically validated system.

- P0: Quantify extraction and source-check sensitivity/specificity on a prespecified, independently adjudicated benchmark. Include wrong groups, cluster/patient counts, denominators, planned/actual samples, rates/percentages/means, tables and figures.
- P0: Independently evaluate false support from the second AI pass. Model agreement does not establish correctness. Keep unresolved claims out of verified exports unless a named reviewer records an evidence-based adjudication.
- P1: Complete real-document UI regression coverage for automatic Tables & images population, edits, rejection, accurate crops, persistence, clipboard and export.
- P1: Expand protocol/PICOTS tests across domains, full public protocol files, multiple registrations and Cochrane workflows. The present pilot is small and does not certify compliance.
- P1: Add a review-team workflow for independent duplicate extraction and disagreement adjudication.
- P1: Obtain Developer ID signing and notarization; test clean-Mac installation and Intel execution.
- P2: Optimize redundant visual requests, add resumable extraction checkpoints and measured latency/cost budgets without weakening checks.
- P2: Consider automatic precise figure/table boxes only after geometry accuracy is measured. Full-page previews are explicitly labeled until a reviewer draws a crop.

Use `./script/test.sh` for the local suite, `./script/build_release.sh` for the universal preview and `python3 script/package.py` for a sanitized downloadable archive. No API keys, local reviews or article PDFs belong in this repository.
