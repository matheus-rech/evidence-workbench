# Extraction design and reporting guidance

These are implementation choices informed by reporting/conduct guidance, not official mandatory universal fields. Applicability depends on the research question, discipline and study design. The workflow requires PICOTT and operational definitions before article import, while recording absent, unclear and inapplicable article data explicitly.

| Workflow / data group | Implemented behavior | Methodological connection |
| --- | --- | --- |
| PICOTT and eligibility | Six defined components and research question required before approval | Prespecification and clear eligibility / synthesis scope |
| Outcomes | Outcome definitions, timepoint labels, selection rules and repeated observations | PRISMA item 10a: define sought outcomes and selection rules |
| Other data items | Definitions, types, units and context levels for every field; custom fields supported | PRISMA item 10b: identify other sought variables and handling of ambiguity |
| Collection methods | Reviewer process, automation role and adjudication approach defined in the plan | PRISMA item 9: report collection and automation methods |
| Study characteristics | Design, setting, registration, population, demographic and intervention data | Cochrane chapter 5: study methods, participants, setting and interventions |
| Study vs report | Stable underlying study ID distinct from report ID; explicit report linkage | Cochrane chapter 5: collate multiple publications about one study |
| Quantitative results | N, events, means, SDs, estimates, precision and analysis context; no silent conversions | Extract sufficient unambiguous data for the planned synthesis |
| Bias evidence | Supporting quotations and prespecified tool/approach; human judgment | Design-specific risk-of-bias assessment |
| Missingness | Reported / not reported / not applicable / unclear; zeros retained as numbers | Avoid assumptions that silently change the evidence |
| Version history | Approved plan snapshots and reasoned amendments | Distinguish prespecified decisions from post-hoc changes |
| Provenance and review | Page, quote, source hash, reviewer, status, model and plan version retained | Accessible, reviewable and reproducible data collection |

Age means/SDs and qualitative findings are deliberately separate from other result types. The app does not convert medians, percentages, SEs, IQRs or graph coordinates into pooled-analysis inputs automatically. For diagnostic, prognostic, qualitative, observational and other reviews, define design-specific fields in the dictionary and mark irrelevant core fields not applicable with a reviewer note.

The mandatory planning fields do not prove that the methods described were conducted. The current verification interface records a named reviewer per observation; it is not an independent/blinded duplicate-extraction system. Cochrane users must arrange the required team workflow and check the relevant current MECIR / Handbook guidance.

References consulted during implementation:

- PRISMA 2020 checklist and its items 9, 10a and 10b: https://www.prisma-statement.org/prisma-2020-checklist
- Cochrane Handbook, chapter 5, collecting data: https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-05
- OpenAI structured outputs: https://developers.openai.com/api/docs/guides/structured-outputs
- OpenAI Responses web search: https://developers.openai.com/api/docs/guides/tools-web-search

Research suggestions must retain their cited sources and remain proposals until the review team accepts them. A relevant-variable research brief is not a systematic search, published core outcome set, or independent validation of the chosen variables.
