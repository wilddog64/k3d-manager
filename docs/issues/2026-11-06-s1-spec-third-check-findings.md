# Third check of S1 review findings

Reviewer: Codex, 2026-11-06. Scope: the eight findings in the second review and the specified oracle and dangling-reference checks.

## Second-review findings

1. **Blocker — status output and oracle: partly closed.** The gate arrays now have the specified object shape, including nonempty examples (plan:251,257; expected.json:349-375), and M1 explicitly compares them (plan:340). However, four output fields are not stored for any synthetic task: `version`, `as_of`, `advisory`, and `bad_lines` (plan:257; expected.json:99-123,349-383,384-405). `bad_lines` is stored once at synthetic level (expected.json:37-38), but the other three have no synthetic stored form. M1 checks exact keys but only compares stored fields, so wrong values for these fields can pass. Store and compare their expected values or explicitly specify equivalent assertions.
2. **Blocker — isolated replay: closed.** M7 retains every coverage marker in original relative order and compares per-task state and aggregate sums (plan:346,363). This preserves the equal-second boundary (synthetic.jsonl:7-9; plan:236).
3. **Blocker — prompt denominator and boundary: closed for S1 by removal.** The follow-up counts tasks charged pre-marker prompts, defines the earliest marker by timestamp, and requires equality to the existing prompt series (prompts-by-model.md:24-28,66-67). The work is no longer part of S1 (plan:189).
4. **Blocker — pre-fix and mutation proof: closed.** N4 tests a different new task for start, compares normalized outcomes with clear controls, and is green on the parent with refusal mutants (plan:225,336,352,360). Refusals snapshot both scratch roots (plan:359); interface-red and behavioural mutation results are separate (plan:336,366).
5. **Should-fix — model history and cardinality: closed for S1 by removal.** The follow-up specifies replay before filtering, fallback, invalid and literal `other`, ranking and union of distinct tasks (prompts-by-model.md:20,32,72); its fixtures list crossing and pre-marker cases (prompts-by-model.md:40).
6. **Should-fix — usable tables: partly closed.** S1 requires all four split targets, a parent join and advisory descriptions (plan:311,345,362); the follow-up requires model joining and descriptions (prompts-by-model.md:34-36,68). Neither acceptance block requires assertions against transformed sample table results, so a join that names the right targets but loses zero or missing values can pass. For S1, require sample-result assertions for a parent without a combine and zero roles (expected.json:52-60,70-77).
7. **Should-fix — split analytics scope: closed.** S1 explicitly moves prompts by model (plan:189); the follow-up preserves the operator goal and starts after S1 lands (prompts-by-model.md:3-10).
8. **Should-fix — negative evidence precision: partly closed.** S1 separates interface-red from behavioural proof, calls for mutants per behaviour, and adds the offline-mark control (plan:336,343,366). N2 also forbids an agent change resetting or adding to the streak (plan:350), but E9 names a model-change reset mutant, not an agent-change mutant or a model/agent change adding a charge (plan:366). A test that misses those defects can pass the listed mutation checks. Add targeted mutants and controls for those independent behaviours.

## Complete status-field check

For `abandoned`, `gates-open`, and `late-assessment`, the stored per-task fields cover `slug`, all six `ladder` rungs, `stall`, `streak`, `unsuccessful`, `runs`, `human_interventions`, both open-gate arrays, `parent`, `role`, and `next_action` (expected.json:100-123,349-405). The values and shapes for these three are producible under the replay rules: in particular the two `gates-open` objects match their source events (synthetic.jsonl:112-115; plan:251,257). The contract additionally requires `version`, `as_of`, `advisory`, and `bad_lines` (plan:257). None is stored in those task objects; only `bad_lines` has a shared synthetic value (expected.json:37-38). Thus the answer to whether every field has a stored form is **no**. The correct no-cutoff values are `v9.9.9`, null, true and 1 respectively (synthetic.jsonl:112; plan:221,257; expected.json:38).

## Removal and contradictions

There is no dangling S1 dependency on the removed prompt analytics: S1 points to the follow-up (plan:189), and its schema, metrics, files and acceptance cover gate and split work (plan:200-217,291-311,321-330,338-372). The follow-up explicitly sequences itself after S1 (prompts-by-model.md:3). The remaining issues above concern test coverage; no additional contradiction found within this narrow check.

Verdict: not ready
