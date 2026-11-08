# Validation record — 0.3

Reproducible entry point: `./script/test.sh`. Latest suite: **68 tests, 67 passed, one skipped, zero failures** on the user's Apple Silicon Mac, Swift 6.3.3, targeting macOS 14+. No third-party dependencies or live credentials are used by the automated suite.

Tests cover plan approval/version gates; typed values and missingness; malformed-row quarantine; source identity/hash/path validation; exact UTF-16/ligature/whitespace anchors and repeated-quote refusal; numeric value-emphasis boundaries; cropped/rotated PDF geometry; explicit visual-verification gates; CSV provenance/formula safety; atomic revision-guarded persistence and backups; structured API schemas, citations, failure handling and bounded multimodal inputs; editable-table shapes, escaping and native RTF table structure; PNG crop geometry; and image-only article import without invented text.

The local Vision OCR integration test skips only its specific CVPixelBuffer allocation failure. OCR accuracy is not established. Image-only article extraction can instead use original page images; verification requires a source box and visual checking.

Actual native UI checks used a real PROSPERO excerpt, two included primary publisher PDFs and a published systematic review. Both articles completed live extraction. Concrete scientific/model errors were found; see REAL_WORLD_PILOT.md. Table conversion, editable TextEdit paste, PNG export, source box persistence, PDF quote highlights and Page text highlights were observed. The main-app selection/highlight gap was fixed and captured, including the new provenance value preview.

In-app background research completed with three source links. A successful job does not establish that all recommendations or citations are correct. No broad accuracy, Cochrane compliance or completed meta-analysis claim is made.

Release validation includes arm64/x86_64 universal compilation and strict ad-hoc bundle signature checks. Intel runtime, clean-Mac installation, Developer ID signing and notarization remain unvalidated. The managed shell's LaunchServices open failed earlier; native app control launched successfully. Do not count the shell --verify path as passed.

The screenshots and report distinguish working examples, rejected failures, code/test-only fixes and untested conditions. API keys, local review workspaces and original article PDFs are excluded from the distributable application/source archive.

## New collection and source-checking work

A persistent Tables & images collection and a separate bounded AI source-checking pass have been implemented after the initial pilot. The latest local suite has 75 tests (74 passed, one OCR skip). Native UI and live-model verification of these newest additions is in progress; do not infer their success from earlier screenshots. The source checker is an error-detection layer, not a factual guarantee.
