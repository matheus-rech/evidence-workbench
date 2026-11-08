# Agent instructions

## Agent skills

### Issue tracker

GitHub Issues on matheus-rech/evidence-workbench, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: bug, enhancement, needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` at the root and ADRs in `docs/adr/`, both created when first needed. See `docs/agents/domain.md`.

### External peers

`auto`: code-review and jury use Codex as a cross-family peer when it is installed, otherwise host-only. See `docs/agents/cross-model.json`.
