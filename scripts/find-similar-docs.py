#!/usr/bin/env python3
"""Find prior art in the docs corpus by semantic similarity. Advisory, never blocking.

Usage:
    scripts/find-similar-docs.py "vault policy denied on an external secret"
    scripts/find-similar-docs.py --k 10 "kine compaction stopped"
    scripts/find-similar-docs.py --json "grafana panel shows no data"

A high score means *read that document before filing a new one* — it does not mean "do not
file". Exit status is always 0: this tool is an aid to the dedup check, and a store that is
down or a missing credential must never block a commit or a Hermes run. Unavailability is
reported on stderr.
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from hermes.prior_art import RetrievalUnavailable, search  # noqa: E402


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("query", nargs="*", help="text to search for")
    parser.add_argument("--k", type=int, default=5, help="results to return (default 5)")
    parser.add_argument("--json", action="store_true", dest="as_json",
                        help="emit JSON instead of a table")
    args = parser.parse_args(argv)

    query = " ".join(args.query).strip()
    if not query:
        print("find-similar-docs: no query given — pass text, e.g. "
              'make find-similar-docs Q="eso 403 on a vault path"', file=sys.stderr)
        return 0

    try:
        results = search(query, k=args.k)
    except RetrievalUnavailable as exc:
        print(f"find-similar-docs: retrieval unavailable — {exc}", file=sys.stderr)
        print("find-similar-docs: falling back to the exact-slug glob is still correct.",
              file=sys.stderr)
        return 0

    if args.as_json:
        print(json.dumps(
            [{"score": s, "path": p, "title": t} for s, p, t in results], indent=2))
        return 0

    if not results:
        print("find-similar-docs: no indexed documents — run `make index-docs` first.")
        return 0

    print(f'Prior art for: "{query}"')
    for score, path, title in results:
        print(f"  {score:5.3f}  {path}")
        print(f"         {title}")
    print("\nA high score means read that file before filing, not that you must not file.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
