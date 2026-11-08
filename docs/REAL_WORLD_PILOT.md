# Real-document pilot: Evidence Workbench 0.3

Date: 8 November 2026 (UTC). This is a development pilot, not a validated scientific extraction benchmark. No pooled meta-analysis was reproduced. The public package contains software and this report, not credentials or the test review workspace.

## Sources and procedure

The public registry record [CRD42023471806](https://www.crd.york.ac.uk/PROSPERO/view/CRD42023471806), version 1.1, was read through the browser. Selected methodological sections were transcribed into a clearly labeled UTF-8 excerpt and imported through the app's native file picker. This was not an original PROSPERO PDF and not a full record import. PROSPERO registration is not peer review.

The corresponding review is Amin et al. (2024), [DOI 10.1186/s12959-024-00614-7](https://doi.org/10.1186/s12959-024-00614-7). Two included primary reports were obtained as original publisher PDFs through Safari:

- Arts et al. (2017), [DOI 10.1371/journal.pone.0170974](https://doi.org/10.1371/journal.pone.0170974), 12 PDF pages.
- Karlsson et al. (2018), [DOI 10.1371/journal.pmed.1002528](https://doi.org/10.1371/journal.pmed.1002528), 17 PDF pages.

The public papers are credited to their authors and publishers; each displays a CC BY 4.0 license. Original PDFs and local pilot outputs are kept outside the distributable source directory.

Actual native UI actions covered protocol import, natural-language planning, selective application of PICOTT/custom-variable proposals, completion and approval of a labeled QA plan, article import and extraction, and navigation to source. An isolated debug app/workspace was subsequently used to preserve the user's open review. Test results distinguish successful actions from interruptions.

## Protocol and natural-language planning

The first live request failed with HTTP 404 using `gpt-6`. Changing the account setting to `gpt-4.1` produced a structured reply. This establishes that successful API authentication alone did not establish model availability. The release now defaults to `gpt-4.1`/`o3` and provides an account model-list action. Model discovery succeeded in the native settings window; research inference with `o3` was not tested.

The planning prompt requested protocol-supported PICOTT, no browsing or published-result hindsight, and explicit handling of missing timing. Population, intervention, comparator, outcomes and RCT eligibility were proposed consistently with the excerpt. Participant follow-up timing was left empty. Review calendar dates were not inserted into that PICOTT component. A clearly labeled QA timing decision was entered manually before approval.

Six custom fields were suggested. Three were applied: cluster-design details, CDSS uptake and reasons for non-prescription. Review calendar dates, a duplicate follow-up field and another broad outcome field were deselected. The calendar-date suggestion was an inappropriate study-level field; the planning instructions now explicitly prohibit that mapping. No improvement in suggestion accuracy is claimed until rerun.

This exercise tested protocol-derived PICOTT via natural language. It did not complete a separate explicit PICOTS-input benchmark or validate multiple PROSPERO registrations, diagnostic/qualitative reviews, or Cochrane review workflows.

## Arts extraction: targeted numeric check

One complete live run with text and original page images produced 85 suggestions, all remaining unverified in the initial saved result. Of 83 source citations, 57 matched page text and 26 did not. These counts measure local anchoring, not factual accuracy. Image findings and inaccurate transcriptions can both lack native-text matches.

Twelve prespecified table-cell checks were compared against the primary article's Table 1 (physical PDF page 7). Each passed for value, arm and assessment label:

| Field | Group | Assessment | Primary source | App suggestion |
|---|---|---|---:|---:|
| Participants | Control | Baseline | 235 | 235 |
| Participants | Intervention | Baseline | 496 | 496 |
| Participants | Control | Post-study | 259 | 259 |
| Participants | Intervention | Post-study | 522 | 522 |
| Age mean, years | Control | Baseline | 74.61 | 74.61 |
| Age SD, years | Control | Baseline | 13.63 | 13.63 |
| Age mean, years | Intervention | Baseline | 72.13 | 72.13 |
| Age SD, years | Intervention | Baseline | 12.46 | 12.46 |
| Age mean, years | Control | Post-study | 73.73 | 73.73 |
| Age SD, years | Control | Post-study | 14.7 | 14.7 |
| Age mean, years | Intervention | Post-study | 72.79 | 72.79 |
| Age SD, years | Intervention | Post-study | 12.61 | 12.61 |

Twelve matching cells do not establish 100% extraction accuracy. The rest of the 85 suggestions were not exhaustively adjudicated, and concrete failures were found:

- A suggested effect of `0.05` was derived from the group percentages rather than directly reported as that effect estimate. Its supporting quotation matched the page, demonstrating that quote matching alone does not establish correctness.
- Counts of 5, 9 and 4 from the image-based CONSORT diagram were entered under a variable whose unit is participants. The figure describes randomization at GP-practice level. Those numbers must not be accepted as patient sample sizes.
- Some suggestions restated objectives or contribution statements as results/funding details. They require rejection or correction rather than automatic acceptance.

Extraction instructions were tightened to distinguish patient and cluster counts, avoid silent arithmetic, exclude cited background-study results, and inspect table headers, denominators, footnotes and timing. These changes reduce a known failure mode in the specification; they do not prove that the model will obey it on all inputs.

## Backward comparison with the published review

The review's demographic table uses intervention/control sample sizes of 522/259 for Arts while listing ages 72.13/74.61. The primary paper labels those sample sizes post-study and those ages baseline; baseline sample sizes are 496/235. Thus a naive equality check against the review would incorrectly collapse different assessment populations. Preserve the primary paper's labels and flag the review's mixed timing rather than treating the review as infallible ground truth.

Karlsson's primary report distinguishes total AF populations, patients eligible for anticoagulation, baseline versus final populations, and cluster-adjusted analyses. Its Table 2 reports different numerators and denominators at baseline and 12 months. Its baseline risk scores are reported with percentile spreads; they must not be silently converted to means/SDs. These distinctions were identified from the original report for the next extraction audit. They have not yet been scored as model successes.

## Provenance and image regions

Native PDF navigation was exercised on the real Arts report. A supporting intervention passage on PDF page 5 was visibly highlighted. The Page text view was then opened, and Show source visibly highlighted exactly the same supporting passage on page 5. This is an observed UI pass for provenance-text highlighting, not a guarantee for every source.

An earlier table-row navigation opened the correct page but left part of the supporting row outside the viewport. The native view now defers scrolling until layout has completed and adds context padding. The final main-app table-row viewport was subsequently checked and captured in screenshot 11.

The new Draw data box tool stores a rectangle in normalized PDF crop-box coordinates, linked to the physical page and observation. Show source restores it as a blue border. Original PDF files are not rewritten. The reviewer must provide a transcription and explicitly check value, units, row/column, group and time point before visual verification. CSV and backups retain the region and visual-review flag; a visual transcription is never labeled an exact native-text match.

Automated checks cover region coordinate validity, cropped/rotated page round trips, backward-compatible citation decoding, persistence serialization, refusal of unchecked/invalid regions, edit invalidation and CSV provenance. The complete native UI sequence was subsequently completed; see the follow-up section below. Automatic AI-generated bounding boxes and figure digitization are not implemented.

## Completed follow-up checks and fixes

The native QA app is a separate bundle and separate workspace. It now displays an orange QA TEST COPY banner and distinct window title. The user's main review was retained. A startup delay was observed in the earlier debug copy; initialization was moved into an explicit view lifecycle load with a loading state. Subsequent launches loaded the actual saved v2 review successfully. The exact cause of the original delay was not conclusively established.

The full draw → attach → transcribe → explicitly check → verify/save → quit → relaunch → Show source sequence succeeded for Arts baseline control age 74.61 years (SD 13.63), physical PDF page 7. The border was adjusted to include the entire row and column header. Verified visual provenance remained distinct from native-text matching. Screenshots 06/07 record this workflow. The final source reader also enables copying/exporting a saved box after navigation.

The user's report that highlights were not visible revealed a UI gap: selecting an observation cleared focus instead of selecting its source. Selection now automatically activates the citation; Show source remains available. The right-hand quotation editor also had no value emphasis. A new provenance preview emphasizes the exact literal value, using numeric boundaries to avoid highlighting 5 inside 15 or 5.2. Main-app screenshot 11 shows 72.79 emphasized alongside the matched source row in Page text. Text highlighting locates evidence and is not scientific verification.

A real Table 1 box was exported as PNG. The first table-to-text attempt returned ragged rows and was rejected (failure screenshot 03). A two-pass conversion now fixes the header schema before transcribing rows with a strict cell count. A repeat succeeded with six rows and seven columns. All 24 group-value cells, eight P values and four empty P-value cells matched the original. The model moved the P-value columns to the right with explicit bracketed headers; the final prompt additionally requires physical left-to-right order. The checked rich table pasted into TextEdit as a real editable table (screenshot 05) and was saved as RTF. HTML was exported through the app. TSV/CSV example files were regenerated from that HTML. Microsoft Word itself was not exercised.

The first complete Karlsson rerun preserved 118 suggestions rather than aborting, but 72 were unclear and 26 reported; most quarantined rows contradicted their missingness labels. The schema was changed to disallow nonempty values under missing labels. The next full run saved 151 suggestions: 139 reported, nine not reported, two not applicable and one unclear (an empty reported value quarantined). The four guideline percentages 70.3/70.0 at baseline and 73.0/71.2 at follow-up, and four rates 49/47 and 12/16 per 1,000 AF patients, were recovered with correct groups. However, model errors remained: rates/percentages also appeared under mean fields, rates appeared as effect estimates, one figure count was 9,292 instead of 8,292, some context labels were misleading, and duplicate narrative/table contexts persisted. These are not acceptable verified data. Final validation blocks explicitly labeled proportions/rates under continuous mean/SD fields; it does not claim to detect every semantic error.

The updated Arts run saved 93 current-v2 observations (81 reported, ten not reported, two unclear), including the previously reviewed age and its saved box. Four OAC percentages 40/48 at baseline and 51/60 post-study, plus endpoint guideline adherence 50/55, were captured. The earlier derived 0.05 effect and notification count as a clinical event were no longer returned as reported numeric values. Cluster-count text under a participant field was quarantined. Baseline adherence 42/50 was still omitted from the dedicated outcome field: extraction completeness is not established. The final import path ignores per-chunk not-reported rows and assigns absence only after all pages, avoiding a missing label from an unrelated chunk alongside reported outcomes. That last adjustment was regression/build checked, not rerun across another full paid extraction.

The in-app o3 background research request completed and retained three returned source links, including Cochrane chapter 23, CONSORT-CRT and a Proctor implementation-outcomes paper copy. The plan remained frozen. Completion and citation retention are observed; the complete brief was not independently adjudicated as a methodological recommendation.

## Current checks and release limits

The final automated suite has 68 tests: 67 passed, one OCR test skipped and no failures. The skip is a managed-environment Vision pixel-buffer allocation failure, not an OCR accuracy pass. Synthetic tests cover malformed-row quarantine, contradictory missingness schema, mean/rate type checks, UTF-16 value emphasis, table dimensions/escaping, actual RTF table structure, image crops and source-region verification. Explicit image-only article import preserves pages without invented text; protocol import still requires readable text.

The release is universal (arm64/x86_64), ad-hoc signed and not notarized. Intel hardware, clean-Mac installation and smooth Gatekeeper distribution remain unvalidated. No Developer ID identity is installed. A downloadable preview is not a trusted public installer. The existing Drive file remains restricted until public sharing is enabled by its owner; no public access is claimed.

This remains a small development pilot, not an empirical accuracy benchmark. It does not establish independent dual-reviewer agreement, full coverage across PROSPERO records, Cochrane review compliance, diagnostic/qualitative review accuracy, figure digitization or reproducible meta-analysis pooling. See the screenshot report and evidence manifest for what each image proves and its limits.
