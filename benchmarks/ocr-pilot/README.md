# Real-paper OCR pilot · 8 November 2026 (US Eastern)

This is an exploratory, source-annotated engineering comparison, **not independent scientific certification**. One operator transcribed the source; there was no second independent human adjudicator, preregistration, blinding or held-out article. Vision output was inspected during setup. Do not promote 123 successful cells into an estimate of general scientific accuracy.

## Inputs and attribution

Seven identical JPEG inputs per engine: Arts et al. (2017), physical page 7 and its Table 1 crop; Karlsson et al. (2018), physical pages 8, 9, 10 and Table 1 (page 9) and Table 2 (page 10) crops. Two repeats per input give 42 runs. Original PDFs remain outside this repository. `input-manifest.json` records original PDF and actual JPEG SHA-256, dimensions and crop coordinates (top-left normalized edges). The three table body grids contain 36 + 75 + 12 = 123 annotated cells including empty cells and n/a.

The included JPEGs reproduce excerpts, with resizing/cropping/JPEG compression, from these open-access primary papers, under their CC BY terms; this attribution and the original authors' rights remain separate from the repository's MIT software license:

- Arts et al. (2017), PLOS ONE, https://doi.org/10.1371/journal.pone.0170974
- Karlsson et al. (2018), PLOS Medicine, https://doi.org/10.1371/journal.pmed.1002528

## Method and scope

`vision_benchmark.swift` uses native `VNRecognizeTextRequest`, revision 3, accurate recognition, language correction and automatic language detection, returning text and line boxes. It does not generate a semantic HTML table. On this Mac, ordinary managed execution failed to create a CVPixelBuffer; execution with access to the normal macOS image services succeeded for all 14 runs. This is recorded as an environment failure, not hidden as a model accuracy result.

`remote_benchmark.py` ran the two pinned models sequentially on the same NVIDIA A10G, with the same actual JPEG bytes checked by hash. GLM revision `2e85a62840ccac27daa451df36c736c4636b8628`; PaddleOCR-VL-1.6 revision `132c45f52c0a26ed5a6b2f6bd8e3985794cc27dd`. Deterministic generation (`do_sample=False`), bfloat16, max 4096 new tokens; GLM Text/Table Recognition prompts; Paddle OCR/Table Recognition prompts. This tests the model recognition stage, **not** either vendor's full layout detection/document parsing SDK. Page-level table omissions cannot be generalized to their complete pipelines.

Core runtime versions and memory limitations are in `environment.json`. Inference time includes preprocessing and generation with CUDA synchronization, excludes downloading, model loading, image network transfer, API queuing and application export. The first repeat is retained. Peak process RSS is cumulative: Paddle ran second, so its process peak may include the first model's earlier allocations. CUDA peak *allocated* excludes reserved/driver memory; Mac unified GPU/ANE memory was not separately measured. Different hardware prevents claiming that a GPU-model latency ratio describes Mac deployment performance.

`gold-source-transcription.json` was transcribed from source images separately from the model response files. An offline scorer matches row labels and fixed body column positions, normalizes decimal formatting/thousands separators, and checks numeric tokens, ±, %, CI, empty and n/a markers. This is **numeric cell association accuracy**, not complete text accuracy, TEDS or independently adjudicated semantic header accuracy. LaTeX-like row labels and Paddle OTSL spans/blank cells are handled explicitly. Unit regression tests demonstrate that swapped numeric columns fail despite perfect bag-of-number recall. Numeric token recall alone is not precision: numbers in the wrong positions may still give 100% recall. No whole-document numeric precision/CER/WER estimate is claimed.

## Measured results

| Engine | Body numeric recall, 3 cropped tables | Numeric cell association, 123 cells × 2 | Median, all 7 inputs × 2 | Median, table crops only | Peak process RSS | Peak CUDA allocated |
|---|---:|---:|---:|---:|---:|---:|
| Apple Vision | 100% | No native structured grid | 0.591 s | see scores.json | 176.4 MiB | not measured |
| GLM-OCR | 100% | 246/246 | 9.427 s | 8.933 s | 3012.3 MiB | 2733.2 MiB |
| PaddleOCR-VL-1.6 | 100% | 246/246 | 24.721 s | 5.380 s | 3501.4 MiB | 1963.7 MiB |

Zero inference exceptions in these 42 runs, **but** Paddle hit the token cap in both full-page Karlsson page-10 runs (~293 s each), so only 12/14 remote outputs were complete for Paddle. Scores derived from those partial responses do not establish page completion. GLM completed 14/14. Vision recognized digits in the selected flowchart (8/8 targets); GLM/Paddle text prompts recovered 0/8 internal flowchart targets. Vision also confused ± signs in Karlsson Table 1. Raw text, line boxes, timings, output tokens and resource measurements are retained in the JSON files. Two repeats are not independent article-level samples and do not justify statistical significance or confidence intervals.

The source itself contains a baseline confidence-interval discrepancy between Karlsson page-9 prose and page-10 Table 2. This gold follows **Table 2**, not an inferred resolution of the discrepancy. Keep that disagreement visible in scientific use.

## Engineering decision and application integration

Keep native PDF text and Apple Vision for local text/boxes; do not replace them with whole-page generative OCR. For **cropped tables**, Paddle has the lowest median latency and lower allocated CUDA memory in this pilot, with tied observed numeric cell accuracy. It is integrated as an optional loopback specialist via `LocalTableClient` and strict OTSL parser. `serve_paddle.py` provides the pinned service and rejects capped generations. It requires CUDA in the measured configuration. **It has not been run as a local model on this Mac, and no Mac performance claim is made.** The app does not download or start weights. Run the service on a separately provisioned CUDA computer, optionally forward its loopback port with SSH, then select local Paddle in Settings. On an unavailable local endpoint it leaves the table unresolved, without sending it remotely.

GLM's community Hugging Face Space is an optional remote alternative, with separate image consent and optional HF token stored separately in Keychain. A real Swift-client Arts Table 1 call passed (7 columns, 6 rows, 9.678 s). The community Space then exhausted the anonymous ZeroGPU quota. Its deployed weights are not guaranteed to match the pinned benchmark revision. The official Paddle Space also returned an API error during a smoke test; that is deployment evidence, not a model-quality score.

The OpenAI vision path remains available. GLM → OpenAI continuity requires an explicit fallback setting plus normal OpenAI consent/key, and every fallback table identifies OpenAI. Local mode takes priority and does not use this remote fallback. Neither specialist validates scientific observations or silently labels them human verified. Caption-bounded crops are provisional and remain distinguished from reviewer-drawn precise boxes.

## Automatic workflow acceptance

The actual application store ran extraction → source checks → discovery → transcription → CSV/HTML/PNG + manifest export on two complete single-page source excerpts (Arts page 7, Karlsson page 10). The first run exposed quota-related missing tables; it is not counted as complete acceptance. After the explicit fallback correction, a fresh isolated run passed in 119.3 s: 74 and 59 observations, 46 and 2 AI-reviewed rows, 2 and 1 transcribed tables, zero human-verified observations. All three final table transcriptions used **OpenAI fallback**, not Paddle or GLM. The 48 annotated body cells in the two gold tables present in that run matched. Raw automatic evidence is in `automatic-acceptance.json`; this does not validate every extracted field, a complete article, or local Paddle inference end to end.

Offline production-parser regression tests consume the real Paddle inference responses, preserve table spans/blank cells/notes and reject malformed grids. These tests are response replay, not another live model run.

## Reproduce and independently adjudicate

1. `python3 script/score_ocr_pilot.py` recomputes scores from the frozen raw files; `python3 -m unittest discover -s script/tests -v` verifies the scorer and packaging gates.
2. Compile `vision_benchmark.swift` with `swiftc ... -framework Vision -framework ImageIO`, then pass the seven JPEG paths, and redirect JSON to a new results directory. macOS image-service access is required.
3. For a new GPU benchmark, use the pinned container in `environment.json`, install `transformers==5.22.2 accelerate pillow psutil`, supply `BENCHMARK_INPUTS` as manifest rows with `remote_url` pointing to the corresponding accessible JPEG bytes, and run `remote_benchmark.py`. No credentials belong in the payload or logs. Record all runtime versions, loading/network time separately, model ordering and a fresh immutable result directory.
4. The optional `serve_paddle.py` is a separate deployment tool. Starting it downloads pinned weights on that CUDA machine. It binds only 127.0.0.1:8766 and exposes `/table`; do not expose it as an unauthenticated public service.
5. Before scientific qualification, obtain a second independent source annotation, adjudicate disagreements, add a held-out multi-article set with scans/negative cases and difficult units, prespecify cell/header/sign/error metrics and assess failures. A blank independent-adjudication worksheet is supplied in the user-facing benchmark outputs. This step remains **pending**.

Model sources/licenses (accessed 8 November 2026): https://huggingface.co/zai-org/GLM-OCR (MIT); https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.6 (Apache-2.0). Apple Vision is an OS framework, not redistributed model weights: https://developer.apple.com/documentation/vision/recognizing-text-in-images. Vendor benchmark claims are not used as our measured results.
