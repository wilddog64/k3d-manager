# Claude Context Window Experiment

## Experiment protocol

1. **Weeks 1–2:** keep the 200K threshold, and record it in the settings table.
2. **Weeks 3–4:** raise the threshold, record the change on the day it is made, and compare the four
   panels over the two 14-day windows.
3. Add each incident row on the day it happens, not from memory at the end.
4. The deciding number is **Claude cost per verified spec**. Compactions and re-reads explain it, and
   incidents set the quality floor.
5. Don't change the threshold more than once per two weeks.

## Settings

| date | auto_compact_tokens | note |
|---|---|---|
| 2026-10-18 | 200000 | Baseline auto-compaction threshold |
| 2026-10-22 | 400000 | Raised to 400K as a trial (`autoCompactWindow` in `.claude/settings.json`); the 200K baseline ran 4 days, not 2 weeks |
| 2026-11-01 | 200000 | Correction, not a new trial: the 400K setting never applied. Sessions run in a 200K context window; the 140 auto-compactions from 2026-10-22 to 2026-11-01 ran at 166K–213K (median 168K), the same as the 72 before (166K–180K). `autoCompactWindow` set back to 200000. A real 400K trial needs a session with a larger context window |

## Incidents

| date | kind | spec | note |
|---|---|---|---|
