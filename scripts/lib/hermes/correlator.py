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
        vault_sealed = self._vault_sealed(records)
        was_active = state.get("incident_active", False)
        notified = state.get("incident_sensors", [])
        if active and not was_active:
            state["incident_active"] = True
            state["incident_sensors"] = contributors
            event = {"kind": "incident", "sensors": contributors,
                     "text": self._template(records, contributors, "incident")}
            return self._enrich(event, state, llm, today, vault_sealed)
        if active and was_active:
            joined = [sensor for sensor in contributors if sensor not in notified]
            if not joined:
                return None
            state["incident_sensors"] = sorted(set(notified) | set(contributors))
            event = {"kind": "escalation", "sensors": contributors,
                     "text": self._template(records, contributors,
                                            f"escalation ({', '.join(joined)} joined)")}
            return self._enrich(event, state, llm, today, vault_sealed)
        if not active and was_active:
            current = {}
            for item in records:
                sensor = item["sensor"]
                current.setdefault(sensor, set()).add(item["status"])
            notified = sorted(set(notified or []))
            degraded_now = sorted(sensor for sensor, statuses in current.items()
                                  if "degraded" in statuses)
            cleared = sorted(sensor for sensor in notified
                             if "healthy" in current.get(sensor, set())
                             and sensor not in degraded_now)
            no_data = sorted(sensor for sensor in notified
                             if sensor not in cleared and sensor not in degraded_now)
            if notified:
                header = f"Hermes correlated incident resolved ({' + '.join(notified)})."
            else:
                header = "Hermes correlated incident resolved (sensors not recorded)."
            display = lambda items: ", ".join(items) if items else "none"
            text = (f"{header} Cleared: {display(cleared)}. "
                    f"Still degraded: {display(degraded_now)}. No data: {display(no_data)}.")
            state["incident_active"] = False
            state["incident_sensors"] = []
            return {"kind": "resolved", "sensors": [], "text": text}
        return None

    @staticmethod
    def _vault_sealed(records):
        return any(item.get("sensor") == "vault_seal" and item.get("status") == "degraded"
                   for item in records)

    @staticmethod
    def _template(records, contributors, kind):
        details = [f"{item['sensor']}: {item['evidence']} ({item['sampled_at']})"
                   for item in records if item["sensor"] in contributors]
        unknown = [item["sensor"] for item in records if item["status"] == "unknown"]
        context = f" Source unavailable: {', '.join(unknown)}." if unknown else ""
        text = f"Hermes {kind}: {' + '.join(contributors)}. {'; '.join(details)}.{context}"
        vault = next((item for item in records if item.get("sensor") == "vault_seal" and
                      item.get("status") == "degraded"), None)
        if vault:
            names = [{"eso": "ESO", "argocd": "ArgoCD"}.get(name, name)
                     for name in sorted(contributors, key=lambda name: (name != "eso", name))
                     if name != "vault_seal"]
            joined = names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1] if names else ""
            consequence = f"{joined} failures listed below follow from it. " if names else ""
            text = (f"Root cause: Vault sealed ({vault.get('evidence', '')}). {consequence}"
                    "The unseal watchdog retries every 5 minutes; nothing to approve unless Vault is still sealed after 15 minutes.\n" + text)
        return text

    def _enrich(self, event, state, llm, today, vault_sealed=False):
        day = today or datetime.now(timezone.utc).date().isoformat()
        budget = state.setdefault("llm_budget", {"day": day, "count": 0})
        if budget.get("day") != day:
            budget.update({"day": day, "count": 0})
        if llm and not vault_sealed and self.provider != "claude" and budget["count"] < self.daily_budget:
            budget["count"] += 1
            try:
                event["text"] = llm(event["text"], self.provider) or event["text"]
            except Exception:
                pass
        return event
