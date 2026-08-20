# Bug: Codex repeats prior answers when replying in Slack threads

## Summary

Slack thread replies sent to `/codex` can repeat earlier agent answers and duplicate `Also filed:` lines instead of answering only the new question.

## Observed Output

Recent Codex thread jobs show repeated `ANSWER:` blocks and duplicate `Also filed:` lines in the job transcript / Slack reply stream. Example output from job artifacts includes the same final answer text more than once in the same thread conversation.

## Root Cause

`bin/k3dm-webhook` fetches the last 20 Slack thread messages and prepends them to the Codex prompt. The current thread-context filter removes status/noise lines, but it does not exclude prior bot-authored replies. That means Codex can see its own previous answers and echo them back on the next turn.

## Fix

Filter bot-authored Slack messages out of `_fetch_thread_context()` before prepending thread history to Codex prompts. Keep human thread messages and error context, but do not feed earlier assistant replies back into the model.
