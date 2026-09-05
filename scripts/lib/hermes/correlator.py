"""Deterministic Hermes incident correlation and bounded LLM enrichment."""

from datetime import datetime, timezone


class Correlator:
    def __init__(self, correlation_window=3, daily_budget=10, provider="gemini"):
        self.correlation_window = correlation_window
        self.daily_budget = daily_budget
        self.provider = provider

    def process(self, records, state, llm=None, today=None):
        history = state.setdefault("correlation_history", [])
        degraded = [item["sensor"] for item in records if item["status"] == "degraded"]
        history.append(degraded)
        del history[:-self.correlation_window]
        contributors = sorted({sensor for cycle in history for sensor in cycle})
        active = len(contributors) >= 2
        was_active = state.get("incident_active", False)
        if active and not was_active:
            state["incident_active"] = True
            event = {"kind": "incident", "sensors": contributors,
                     "text": self._template(records, contributors, "incident")}
            return self._enrich(event, state, llm, today)
        if not active and was_active:
            state["incident_active"] = False
            return {"kind": "resolved", "sensors": [], "text": "Hermes correlated incident resolved."}
        return None

    @staticmethod
    def _template(records, contributors, kind):
        details = [f"{item['sensor']}: {item['evidence']} ({item['sampled_at']})"
                   for item in records if item["sensor"] in contributors]
        unknown = [item["sensor"] for item in records if item["status"] == "unknown"]
        context = f" Source unavailable: {', '.join(unknown)}." if unknown else ""
        return f"Hermes {kind}: {' + '.join(contributors)}. {'; '.join(details)}.{context}"

    def _enrich(self, event, state, llm, today):
        day = today or datetime.now(timezone.utc).date().isoformat()
        budget = state.setdefault("llm_budget", {"day": day, "count": 0})
        if budget.get("day") != day:
            budget.update({"day": day, "count": 0})
        if llm and self.provider != "claude" and budget["count"] < self.daily_budget:
            budget["count"] += 1
            try:
                event["text"] = llm(event["text"], self.provider) or event["text"]
            except Exception:
                pass
        return event
