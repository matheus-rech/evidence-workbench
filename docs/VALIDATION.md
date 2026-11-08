# Validation record — development checkpoint

Reproducible entry point: `./script/test.sh`. Latest suite: **99 tests, zero failures, one opt-in live test skipped** on the user's Apple Silicon Mac, Swift 6.3.3, targeting macOS 14+ (the OCR integration test skips only when Vision cannot allocate its pixel buffer; it ran in the latest run). The earlier checkpoint recorded 75 tests, 74 passed, one skipped. No third-party dependencies or live credentials are used by the automated suite.

Tests cover plan approval/version gates; typed values and missingness; malformed-row quarantine; source identity/hash/path validation; exact UTF-16/ligature/whitespace anchors and repeated-quote refusal; numeric value-emphasis boundaries; cropped/rotated PDF geometry; explicit visual-verification gates; CSV provenance/formula safety; atomic revision-guarded persistence and backups; structured API schemas, citations, failure handling and bounded multimodal inputs; editable-table shapes, escaping and native RTF table structure; PNG crop geometry; and image-only article import without invented text.

The local Vision OCR integration test skips only its specific CVPixelBuffer allocation failure. OCR accuracy is not established. Image-only article extraction can instead use original page images; verification requires a source box and visual checking.

Actual native UI checks used a real PROSPERO excerpt, two included primary publisher PDFs and a published systematic review. Both articles completed live extraction. Concrete scientific/model errors were found; see REAL_WORLD_PILOT.md. Table conversion, editable TextEdit paste, PNG export, source box persistence, PDF quote highlights and Page text highlights were observed. The main-app selection/highlight gap was fixed and captured, including the new provenance value preview.

In-app background research completed with three source links. A successful job does not establish that all recommendations or citations are correct. No broad accuracy, Cochrane compliance or completed meta-analysis claim is made.

Release validation includes arm64/x86_64 universal compilation and strict ad-hoc bundle signature checks. Intel runtime, clean-Mac installation, Developer ID signing and notarization remain unvalidated. The managed shell's LaunchServices open failed earlier; native app control launched successfully. Do not count the shell --verify path as passed.

The screenshots and report distinguish working examples, rejected failures, code/test-only fixes and untested conditions. API keys, local review workspaces and original article PDFs are excluded from the distributable application/source archive.

## Code review follow-up (8 November 2026)

A full read of the source produced three high-severity findings and several medium ones; all were fixed test-first (each new test was run and observed failing for the stated reason before the change, then the full suite was run green). The suite now has **95 tests, 0 failures** on the same Mac (Swift 6.3.3). Fixed and covered:

- An AI re-check of a saved claim demoted verified rows, deleted the reviewer's adjudication text, recorded transport failures as "unclear" verdicts and moved the row to the current plan version (so an AI verdict could admit an earlier-plan row into the verified export). It now records the verdict only; failures are reported as errors. `WorkspaceStoreTests`.
- One unreadable review folder hid every review. `ProjectRepository.list()` now returns the readable reviews plus a named failure list, surfaced as a notice. `RepositoryTests.testListIsolatesUnreadableProjectDirectories`.
- The source checker received the extractor's free-text note while its prompt claimed otherwise. The payload now carries value, context, plan definition and unit only. `testSourceCheckerNeverSeesTheExtractorNoteButGetsThePlanUnit`.
- Project files from earlier builds failed to decode when a later-added key was absent. Lenient decoding with defaults; identity keys (review, report, observation, source asset and field ids) are still required, so a record without its id is refused instead of being given a new one. `LegacyDecodingTests`. The pilot QA workspace (3 reviews) and the live Application Support workspace (2 reviews) both load with zero failures.
- A configured key file without the variable blocked the Keychain entry. It now falls back only in that case; a deleted, moved, symlinked or oversized file is reported (a follow-up review caught that the first version fell back on every file error). `AppCredentialsTests`.
- 120 s idle timeout against non-streaming responses of up to 16,000 tokens; now 600 s / 900 s. `testTransportAllowsLongNonStreamingResponses`.
- The full field dictionary was resent inside the plan context on every extraction call. `testExtractionSendsEachVariableDefinitionOnce`.
- Absence rows were added for variables the reviewer had already recorded. `testAbsenceRowsSkipVariablesTheReviewerAlreadyRecorded`.
- A malformed model row with an out-of-page region was dropped instead of quarantined. `testInvalidRegionIsDroppedAndTheRowIsRetainedForCorrection`.
- `html`/`htm` were installable but not loadable. `testOnlyLoadableDocumentTypesCanBeInstalled`.
- Research that failed to start left an unanswered user turn in the chat. `testFailedResearchStartLeavesAnExplanatoryAssistantMessage`.

Changed without a dedicated unit test (UI or refactor under existing tests): document reads and DOCX parsing moved off the main actor (`DocumentLoaderTests` unchanged and green); the Settings copy and README data-flow list now name the source-check, discovery and table-conversion transmissions; Settings warns when the checker and extractor identifiers match and offers **Use Keychain instead**; the extraction audit entry names both models; the Dataset page's verified count applies the same resolved filter as the export; cell edits in the sheet opened by **Convert boxed table to editable text** now save to the Tables & images entry. The rebuilt `dist/EvidenceWorkbench.app` was launched against an empty temporary workspace, ran, and quit on request; no live paid extraction was rerun as part of this change set.

## Live end-to-end check (8 November 2026)

`LiveExtractionTests` is an opt-in, paid test. It runs the app's own pipeline (DocumentLoader, PDFPageImages, `OpenAIClient.extract`, ReviewEngine quarantine and consolidation, `OpenAIClient.checkSources`) on physical page 7 of Arts et al. 2017 with page text plus the page image, and scores the result against the 12 Table 1 cells hand-checked in REAL_WORLD_PILOT.md. It is skipped unless `EW_LIVE_EXTRACTION_PDF`, `EW_LIVE_KEY_FILE` and `EW_LIVE_REPORT` are set; it writes a JSON report and asserts only the pipeline's invariants, because model output varies between runs.

First run, `gpt-4.1` extracting and `gpt-4.1` checking: 12 of 12 cells matched on value, arm and assessment time; 12 reported rows, none outside the truth set; every quote anchored on the cited page; the checker returned `supported` for all 12. One labelling defect: the model put "baseline" or "post-study" into the comparator field (`vs baseline`) as well as the time point, so context labels still need review.

Limits: one page, one run, and twelve easy cells from a clean native-text table. With no wrong rows to judge, the checker's false-support rate is untested, and the checker was the same model as the extractor. This shows the paid path works end to end after the 8 November changes. It is not an accuracy estimate.

## New collection and source-checking work

A persistent Tables & images collection and a separate bounded AI source-checking pass have been implemented after the initial pilot. The latest local suite has 75 tests (74 passed, one OCR skip). Native UI and live-model verification of these newest additions is in progress; do not infer their success from earlier screenshots. The source checker is an error-detection layer, not a factual guarantee.
