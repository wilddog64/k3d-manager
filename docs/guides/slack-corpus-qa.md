# Slack documentation Q&A

`/ask-docs [--sources] <question>` searches the documentation corpus and posts a concise, sourced
answer. In `SLACK_CHANNEL_ID`, `/ask` and `/ask-docs` start a bot-authored thread and post the
answer in it; elsewhere they retain Slack's unthreaded `response_url` delivery. `--sources` skips
the summary model and returns the matching document scores and paths. It is read-only: the model
receives bounded excerpts and cannot run tools. Answers are advisory and sourced, not authoritative;
read the listed documents before making an operational decision.

The command is available to `reader` users, the same tier as `/ask` and `/cluster-status`. Readers
already receive live topology and cluster-aware agent answers, so bounded excerpts from this corpus
do not widen disclosure. Excerpts are redacted, and the allowlist is limited to the corpus dirs;
the question text is never logged.

Returnable paths are restricted to these directories:

- `docs/bugs/`
- `docs/issues/`
- `docs/plans/`
- `docs/retro/`

Each result contributes at most 600 characters from the file, plus its title. Credentials, IPv4
addresses, and phone-number-shaped strings are redacted. Every response carries a `Sources:` list;
no-match and unavailable results carry `Sources: none`.

## Retrieval choice

The embedding scorer was chosen because it beat the TF-IDF control on bugs and tied it elsewhere:

| Scorer | Bugs | Issues | Plans | Retro | Intrusion@5 |
|---|---:|---:|---:|---:|---|
| Embeddings | .875 | .833 | 1 | 1 | .286 / .5 / .75 / .5 |
| TF-IDF control | .75 | .833 | 1 | 1 | .071 / .5 / 1 / .25 |

The directory order for intrusion is bugs / issues / plans / retro. `/ask-docs` therefore uses the
existing `prior_art.search()` embedding path. The acceptance floor is **PROVISIONAL** while Claude
calibrates against the live store: `ASK_DOCS_MIN_SCORE` defaults to `0.60` and can be overridden
with `K3DM_ASK_DOCS_MIN_SCORE`.

For recent questions that name a document kind (bugs, issues, plans/specs, or retros), `/ask-docs` lists the newest documents of that kind by date; "fixed", "verified", or "resolved" narrows the results to done statuses. Other recent questions still rank by similarity and then date.
