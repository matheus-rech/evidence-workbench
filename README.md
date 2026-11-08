# Evidence Workbench for macOS

A native, local-first extraction workspace for systematic reviews across research questions and study designs. The app replaces the single-condition HTML prototype with SwiftUI, PDFKit, Vision OCR, a versioned review plan, typed extraction fields and explicit human verification.

## Open the app

The packaged build is `dist/EvidenceWorkbench.app`. The universal release contains Apple Silicon and Intel executables and requires macOS 14 or later. Apple Silicon was exercised locally; Intel was cross-compiled and has not been run on Intel hardware. The current build is ad-hoc signed for local use, not Developer ID signed or notarized for public distribution.

The source package has no third-party dependencies. To build and launch with Xcode's Swift toolchain:

```sh
./script/build_and_run.sh
```

The script stages a real `.app` bundle. Development launches use `LocalData/` inside the source project; opening the packaged app normally uses `~/Library/Application Support/EvidenceWorkbench/Reviews/`. These locations are separate. Use the build script from the repository root. Local editor configuration is not required.

Run verification with:

```sh
./script/test.sh
./script/build_and_run.sh --verify
```

Build without opening a window with `./script/build_and_run.sh --build-only`. The run script also supports `--debug`, `--logs` and `--telemetry`. There is no app-specific telemetry collection; the last flag is a diagnostic log filter.

## Workflow

1. Create a review. Import a PROSPERO, OSF or other protocol as PDF, DOCX, UTF-8 TXT or Markdown, or write the question manually.
2. Define the research question and all six PICOTT components: population, intervention/exposure, comparator, outcomes, timing and study types. Explicitly enter “Not applicable” for genuinely inapplicable dimensions.
3. Set the review framework and methods: extraction/reviewer process, disagreement resolution, outcome selection, missing data, risk-of-bias approach and synthesis plan.
4. Review the 37 core extraction fields (including reported proportions and rates). Customize their definitions/types/units and add topic-specific fields manually. The planning agent can propose PICOTT and additional variables from protocols, instructions or a cited research brief. Select and apply proposals to the draft; nothing is applied automatically.
5. Save and approve the plan. Article import is blocked until the plan is complete and approved.
6. Import reports. The original files and their SHA-256 hashes are retained. Link multiple reports to the same underlying study. Declare peer-review status after checking it; filenames do not establish peer review.
7. Run AI extraction or create manual observations. Every arm, comparator, outcome, time point, subgroup and analysis can have separate observations.
8. Review values beside the original source. Attach an exact quotation and page. Explicitly verify each reported value under the named reviewer. Missingness needs a reviewer explanation; zero is a reported number, never a substitute for missing data.
9. Export verified current-plan observations, an all-status CSV with provenance, or a full review backup. CSV is long-format and preserves study/report IDs, context, quotes, status, units and plan versions.

Approved plans are frozen. A reasoned amendment preserves the earlier plan and increments its version. Earlier observations are available through an explicit toggle with their original version; they require rechecking before entering the new version's verified-only export.

## Planning agent and deep research

Open **AI & preferences** and add your OpenAI API key. The key is stored in macOS Keychain, not project files, browser storage or exports. Alternatively, choose a local `OPENAI_API_KEY` env file (see Local API configuration); a configured file takes precedence and the Keychain entry is used when the file lacks the variable. Settings shows which source is active and offers **Use Keychain instead**. Enable cloud AI only when you intend to send selected content to the API. API calls can incur charges.

The same composer supports ordinary planning and **Deep research**. Ordinary planning uses structured responses to propose custom fields and PICOTT changes. Research uses a configurable reasoning model, Responses API web search, high reasoning effort and a background job. The job ID is saved, so polling can resume after relaunch without starting another job. Completed reports retain citation links returned by the API. Proposed fields are then prepared from the research report and require manual selection/application.

Default model identifiers are `gpt-4.1` for extraction/planning, `gpt-4.1` for the independent source checker and `o3` for research. The checker default equals the extractor default, so its agreement is correlated with the extractor's errors; Settings shows a warning while the two identifiers match, and each extraction's audit entry names both models. In Settings, use **Load account model list** to inspect available identifiers; listing does not prove feature compatibility. A live pilot succeeded with `gpt-4.1`; the former `gpt-6` setting returned HTTP 404 for this account. Change them to models available to your API account. The selected extraction model must support strict structured outputs. The research model must support `web_search`, high reasoning effort and background responses. There is no silent fallback to another provider or retired dedicated research model.

Cloud data flow:

- Planning: saved plan, imported protocol text and recent review chat.
- Research: saved plan, imported protocol text and the requested research question; server-side background storage is enabled for resumability.
- Extraction: approved field definitions for the current batch, the plan without its field dictionary, bounded article-text chunks and, by default, original page images (up to three pages per batch); response storage is explicitly disabled. Provider-level retention policies still apply.
- Independent source check (after extraction, or on request for one claim): each AI claim as value, context, the plan's definition and unit; the cited page text with its neighbouring pages; and the same page images when visual extraction is on. The extractor's note and confidence are never sent, so the checker reads the source rather than the first model's explanation.
- Tables & images discovery: page images in batches of three for every page of a report. Table conversion: the boxed image and the untrusted table label. Both run with the extraction model and response storage disabled.
- Manual entry, local OCR, native PDF viewing, saving and export do not require cloud AI.

Authentication was verified from the native app against the OpenAI models endpoint. Paid protocol planning and two primary-article extraction workflows were exercised with `gpt-4.1`. The small pilot found extraction errors; it is not a clinical/research accuracy certification. A live o3 background research brief completed and retained three returned citations; its entire content was not independently adjudicated. Request construction, response parsing, failure handling and research-job structure are tested using an injected mock transport. No API key is bundled.

## Sources, OCR and verification

Native PDFKit replaces the old PDF.js dependency and browser canvas annotations. Source navigation uses PDF text selections and real page numbers, avoiding CSS/canvas-coordinate mismatches. Scanned pages use sequential local Vision OCR at bounded image resolution. OCR quotes match the transcription; users still need to inspect the original image for recognition errors.

Limits are explicit: 100 MB per document, 400 PDF pages and two million extracted characters. Documents exceeding those limits must be split into linked reports. The app never substitutes demo data for unreadable documents. Extraction sends all readable chunks in sequential batches of up to three pages and 12 fields, validates typed results, and only applies a complete staged run. An interrupted run does not replace saved observations.

Confidence scores are model self-reports on a single integer 0–100 scale. They are not empirically calibrated probabilities. A source quote match establishes that text exists on a page, not that the value, denominator, group, timing or interpretation is correct. Verification is a separate human action. Editing a value or its context clears prior source linkage; a quote must be deliberately attached again. Re-extraction preserves edited, verified and rejected rows.

## Methodological scope

The core extraction dictionary is app-specific and informed by [PRISMA 2020](https://www.prisma-statement.org/prisma-2020-checklist) and [Cochrane Handbook chapter 5](https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-05). It is not a reproduction of an official extraction form or a compliance certificate. See `docs/METHODS.md` for mappings and limits.

The app prepares data for systematic review and meta-analysis; it does not run statistical pooling, calculate certainty ratings, automatically verify publication/retraction status, perform figure digitization, or implement blinded dual-reviewer adjudication. Reviewer-process requirements and design-specific analysis decisions must be specified by the review team. The versioned data model preserves separate reports and repeated contexts, but overlapping publications and dependent comparisons must still be adjudicated before synthesis.

Visual extraction now sends labeled original page images together with page text, allowing the model to inspect table headers, layout and footnotes. This does not guarantee that complex tables or chart estimates are reconstructed accurately. Inspect those sources manually; add explicit rows and notes for any justified derivations. No pooled-effect estimates are generated automatically.

## Persistence and security

Projects are saved independently with atomic JSON replacement, a revision guard and an operating-system write lock. UI success follows the disk commit. A review folder that cannot be opened (corrupt JSON, a newer schema version, a half-written directory) is reported by name in a notice and left untouched; the other reviews still load. Project files written by earlier builds decode with defaults for fields that later builds added.

An AI source check requested from the observation editor records a verdict and nothing else: it never changes review status, the reviewer, the adjudication text or the observation's plan version, and a failed request is reported as an error rather than stored as an "unclear" verdict. Verified-only export already excludes AI claims that are neither supported nor adjudicated, so a contradicted verdict on a verified row removes it from the export without erasing the reviewer's work. Only a reviewer save or verification moves an observation to the current plan version. Original sources are stored under content-addressed filenames and checked by hash when opened. Backup restoration validates attachment paths and hashes and creates a separate review. CSV fields are quoted and formula-like text is neutralized for spreadsheet opening; numeric negative values are preserved.

The application renders messages as native text; model output, filenames and quotations are not interpreted as HTML. Network requests use HTTPS and bearer authorization. Server error bodies are not echoed. No network call is retried after an ambiguous transport failure; explicit rate-limit responses have a bounded retry policy. Structured calls are not streamed, so the idle timeout is 600 seconds (900 seconds per request overall) to cover a long single generation.

The audit trail records plan approvals/amendments, document imports, source hashes, edits with before/after values and context, verification, report linkage and research activity. It is an editable local project log, not a tamper-evident regulatory record or shared multiuser database. Keep backups. Plan and observation editors block in-app navigation while edits are unsaved; save before closing a window. Quitting the app is blocked while draft changes or a foreground operation remain.

## Code map

- `Sources/ReviewCore`: review models, core dictionary, validation, merge rules, exports, persistence and injectable OpenAI Responses client.
- `Sources/EvidenceWorkbench/Views`: native split-view workspace, protocol editor, source reader, extraction review, dataset, audit and planning agent.
- `Sources/EvidenceWorkbench/Services`: PDF/text/DOCX loading, bounded local OCR, Keychain and file panels.
- `Sources/EvidenceWorkbench/Stores`: serialized commits and cancellable extraction/research orchestration.
- `Tests`: core regression tests and native-document integration tests.

The original uploaded HTML has not been overwritten. Existing browser IndexedDB data is not migrated automatically; retain its original exports separately.

## Visual extraction and source-anchor update

Visual extraction is enabled by default and can be disabled in Settings. Original PDF pages are rendered locally as bounded JPEG images, labeled with their physical PDF page number, and sent alongside text to a compatible vision model. A dedicated key was created after explicit written approval and saved in the Git-ignored `.env.local` file. Native app authentication succeeded. Source-package builds read this external file directly without copying it into the app bundle; downloaded packages contain no credential. Cloud content processing remains controlled by the Settings consent toggle.

Quotes now resolve to original UTF-16 offsets on the cited page. Whitespace and common printed ligatures can be reconciled without changing numeric values or punctuation. Repeated quotations require the reviewer to select the intended occurrence. An invalid stored offset never falls back to another occurrence. Native PDFKit selections provide highlight geometry in PDF page coordinates, so zoom, crop and rotation do not require guessed screen coordinates. Source navigation clears stale highlights and can be triggered again for the same quote.

For an OCR transcription without an underlying selectable PDF text layer, the app can show the matched transcription and original page, but does not invent a spatial highlight on the scanned image. Image-only findings require a drawn source region, reviewer transcription and explicit visual check before verification. Image-only article PDFs can be imported without successful OCR for visual extraction; protocol imports still require readable text. OCR accuracy remains unvalidated in this managed environment. No universal accuracy guarantee is implied.

## Local API configuration

The approved local `.env.local` file contains `OPENAI_API_KEY` and must never be committed, shared, or included in a backup of the source directory. The packaging script explicitly excludes env files and checks that the configured key is absent from archive contents. The app can use a chosen local key file, the source-project file beside its `dist` folder, or its Keychain entry. Local files are parsed as data, never sourced as shell scripts. Use **Check OpenAI connection** for a non-inference authentication test. If you move the app, use **Choose local key file…** to select the original approved file. No secret is bundled in the downloadable app.


## Downloading on another Mac and sharing

Unzip `EvidenceWorkbench_macOS.zip` and copy `EvidenceWorkbench/dist/EvidenceWorkbench.app` to Applications. The universal release requires macOS 14+. You can send this sanitized ZIP through AirDrop or a download service. For a public Google Drive link, upload the ZIP, open Share, change General access to Anyone with the link, choose Viewer, and copy the link. A private ChatGPT download link by itself does not grant others access.

Each user configures their own OpenAI API access in AI & preferences. No API key, local review data or validation workspace is shipped. For your own review data, use the app's Back Up Review and Restore backup actions separately.

This preview is ad-hoc signed. No Developer ID signing identity is available on the build machine, so the archive is not notarized and Gatekeeper may block it on another Mac. A smooth public installer requires Developer ID signing and notarization; the current archive should not be described as a trusted public release. The app does not disable Gatekeeper or other security settings.

Build a universal release with `./script/build_release.sh`; create the sanitized source/app ZIP with `python3 script/package.py`.

## Image regions and provenance

For data embedded as an image, enable **Draw data box**, drag around the relevant region on one physical PDF page, select an observation, and choose **Attach drawn box**. Supply the transcription and check the displayed value, units, row/column, group and time point against the original before visual verification. **Show source** restores the stored box. The original PDF is unchanged. Coordinates use fractions of the crop box in PDF page space; they are retained in review backups and CSV exports.

Image evidence has different provenance from machine-matched text: it retains a reviewer-check flag and region coordinates, with `quotes_match=false`. A source match or box alone never verifies a scientific result. The app does not currently generate automatic AI bounding boxes.

The Page text view highlights the exact supporting passage through the same UTF-16/quote resolver used for PDF text. Image-region evidence is explicitly labeled instead of being presented as an exact native-text match. See `docs/REAL_WORLD_PILOT.md` for the completed checks, known failures and UI checks interrupted by the test environment.

Malformed model values are retained as unclear suggestions with their original value and validation reason in the reviewer note. They are not silently repaired or accepted. Unknown source/variable references and malformed response envelopes still fail closed.

## Editable tables and image export

Use **Copy / export** in the source reader to copy or save the current page or a drawn region as PNG. For a table, include all headers, cells and footnotes in the box, then select **Convert boxed table to editable text**. This sends only the selected image to the configured OpenAI extraction model. Review and edit cells beside the original image, then explicitly check the table before export.

**Copy for Word / rich text** supplies a real HTML/RTF table with a plain TSV fallback; **Copy TSV** supports spreadsheets. Export offers RTF, HTML, TSV and CSV. HTML/RTF retain the source filename, page, SHA-256 and normalized region. A live table was pasted successfully into TextEdit as an editable table; Microsoft Word itself has not been exercised. Table preparation does not automatically create or verify extraction observations.

Older approved plans retain their dictionaries. Use a documented amendment and **Add percentage and rate outcome fields** to add the two new result fields. Missing outcome mean/SD does not establish that binary outcomes are absent. After an amendment, old-plan observations are hidden by default and can be shown explicitly for rechecking.

Selecting an observation now automatically navigates to and highlights its citation. The provenance preview emphasizes a literal value inside its quote; numeric boundaries prevent substring matches. Edit the quotation using its disclosure control. If a quote is missing or ambiguous, the app reports that and draws no guessed match.

## Project preservation and next session

The private GitHub repository is https://github.com/matheus-rech/evidence-workbench. Clone it on another Mac with an account that has access:

```sh
git clone https://github.com/matheus-rech/evidence-workbench.git
cd evidence-workbench
./script/test.sh
./script/build_and_run.sh
```

Requires macOS 14 or later and Xcode's Swift toolchain. Credentials, imported PDFs, local reviews and built app bundles are excluded. Back up or export review data separately from the source repository. A private source repository does not provide a public app download.

The current development checkpoint includes a persistent **Tables & images** collection, automatic asset discovery after visual extraction, editable table export and a separate AI source-checking context. These additions remain under real-document validation. AI support is not human verification or a guarantee of accuracy. Read [the validation record](docs/VALIDATION.md), [the pilot findings](docs/REAL_WORLD_PILOT.md) and [the backlog](docs/ROADMAP.md) before extending or distributing the app.
