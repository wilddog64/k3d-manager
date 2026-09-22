# E2E triage corpus

This is a labelled regression set for `hermes.e2e_triage.classify` and `service_for`.
The 11 real entries are transcribed from the five machine-filed bug documents dated
2026-09-16: three from the cart contract-drift document, three from cross-service,
two from orders, one from products, and two from payments. The remaining entries are
clearly marked synthetic and cover classes and edge cases absent from those documents,
including Tier 2 ports and redaction.

The 11 real labelled samples are sufficient to detect classifier regressions and
insufficient to validate any probabilistic or confidence-scored triage method. Do not
cite this corpus as evidence of a calibrated threshold.

When a new E2E failure is triaged, add one JSON object with a unique `id`, the source bug
document (or `synthetic`), the exact spec file and error, and the expected classifier and
routing labels. Keep synthetic entries explicitly marked and transcribe real sample text
verbatim.
