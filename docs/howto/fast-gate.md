# Fast local gate

Run `make fast-gate` before pushing, or `make fast-gate BASE=<revision>` to choose the base. The pre-push hook and dispatcher landing run it automatically. It targets under 60 seconds for a typical push.

The gate runs the static BATS suites in `scripts/etc/fast-gate/static.list`, changed tests, and up to 40 additional tests that name a changed file. It checks changed shell scripts, workflows, and Markdown with ShellCheck, yamllint, and the doc-link checker. Selected tests run four at a time by default; set `FAST_GATE_JOBS` to a positive integer to change concurrency. Results print in selection order, with the last 20 output lines shown for failures. Missing tools are reported as skips. Pytest runs behind the test tripwire. When promtool is absent, the gate lists the affected marked tests it skips while running the remaining tests in those files. The slowest check and total time appear at the end.

Add a repo-relative BATS path to the static list when a quick suite must run for every change. `K3DM_SKIP_FAST_GATE=1` is an operator-only bypass; agents must fix failures instead.
