# Evidence Workbench — isolated review build 0.5.0

Based on upstream `meta` at `d24d4498ab61d1bfa30edf3e9cccbcb5325ecd5d`. This review copy contains audit P0/P1 fixes and an opt-in automatic AI workflow. It does not replace an installed application or migrate its data.

## Open and build

Open `dist/EvidenceWorkbenchReview.app`. It has a distinct bundle ID, executable, preferences and Keychain service. Its default review files live in `dist/ReviewData/` beside the app, never in the main app's default workspace. Keep it in a writable folder. Do not point `--workspace` at your production reviews. Start with disposable documents or use Restore backup to create a separate review.

```sh
bash script/test.sh
python3 -m unittest discover -s script/tests -v
bash script/build_review.sh --build-only
bash script/build_review.sh --release
python3 script/package.py
```

`--release` builds arm64 and x86_64; `--run` builds and opens the isolated bundle. Scripts do not terminate other apps. Builds are ad-hoc signed, not Developer ID signed or notarized. Intel runtime and clean-Mac installation remain unvalidated. The bundle records its source commit and a source content digest; the ZIP records SHA-256 per file. Sources are packaged by allowlist; editor settings, workspaces and env files are excluded even if tracked.

## Assisted or automatic

Define and approve a review plan first. Import reports. Enable cloud AI in this review app's settings and configure its own credential if you want AI processing; no credential is shipped or copied from the main app.

- **Assisted:** Extract with AI saves suggestions. Human Verify & save requires a named reviewer, valid provenance and an explicit source decision for AI values, even if a checker agrees.
- **Automatic review & export · AI decisions:** On Extract with AI, extraction, source checking, optional Tables & images discovery/transcription and export run without per-row human approval. Accepted rows are labeled `aiReviewed`, not `verified`. The run writes a new `exports/<UUID>/` folder inside that review: full observations, AI-reviewed subset, asset images, editable tables and manifest. Repeated runs create new folders rather than overwrite outputs. Unanchored, OCR-only, contradicted or otherwise unresolved results remain in the complete output for visibility. Table transcriptions and full-page figure previews remain AI drafts; precise automated crop generation and chart digitization are not implemented.

AI-reviewed rows can still be scientifically wrong. The automatic subset requires fresh source/field-bound checker support, exact non-OCR source quotes, valid types and literal numeric support. Those checks do not establish correct semantics for every table or population. Human verification and AI acceptance are distinct export categories. Automatic mode provides a complete labeled handoff, not a claim of perfect extraction.

## Integrity changes

All observation verification and dataset exports rehash originals. Saved human/AI decisions bind source ID/hash, cached transcription, exact citations, field definition and plan version. Loads reject broken/duplicate identities and quarantine legacy/inconsistent verified states as editable while retaining values and prior reviewer in the audit trail. Re-review is necessary before those values enter verified export. No automatic migration writes to the original workspace occur. New saves use schema 2; schema-1 copies can be imported and re-reviewed. Older app versions do not understand AI-reviewed states: do not transfer this review workspace back into the old application.

`ReviewCore` is the typed model/validation/persistence/API layer; SwiftUI, PDFKit, Vision and AppKit implement the native UI. There are no external Swift package dependencies. Documents are local JSON/files; audit history is editable and not a cryptographic regulatory record.

## OCR and evaluation

Apple Vision is still the local OCR engine; PDFKit supplies native text. OpenAI visual extraction is a separate opt-in cloud feature. [Open local OCR comparison and benchmark plan](docs/OCR_OPTIONS.md) covers PaddleOCR-VL, GLM-OCR/MLX, LightOnOCR and olmOCR. No new OCR model has been installed or declared a local benchmark winner.

[Source-check benchmark](benchmarks/README.md) contains 20 frozen regression claims with positive and negative cases, a strict scorer and the historically observed false-support case. It is a small engineering regression corpus. Independent second adjudication, held-out model accuracy and full OCR comparisons remain pending; unit-test success is not a model-quality estimate. Live extraction tests are paid and opt-in. Local suite reports OCR/environment skips explicitly. CI configuration is provided for macOS but has not been run on GitHub by this task.

## Data sent to OpenAI

Planning: plan, protocols and recent chat. Extraction: approved definitions, text and optional images. Checker: claim/context, definition/unit and neighboring source pages/images, without extractor rationale/confidence. Assets: source-page images; tables: selected image. Structured calls set `store=false`; background research uses web search and `store=true`. Model availability and charges depend on your account. Manual work, PDF viewing and Vision OCR remain offline.

Protocol approvals and independent human reviewer conduct are responsibilities of the review team. The software does not certify Cochrane/PRISMA compliance or perform statistical pooling. Original pilot documents under `docs/REAL_WORLD_PILOT.md` and `docs/VALIDATION.md` are historical records, not validation of this corrected build.

## License

MIT, as selected by the repository owner for this review copy. Article PDFs, figures, model weights and external runtimes retain their respective licenses. Nothing has been pushed or published by this task.
