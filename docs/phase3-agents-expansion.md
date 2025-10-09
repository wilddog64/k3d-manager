
---

## 📄 `docs/phase3-agents-expansion.md`

```markdown
# Phase 3 — Agent & Job Expansion

After credentials are migrated, scale up agents and import more jobs incrementally.

---

## 1️⃣ Add More Windows Agents

- Create additional Windows VMs on vSphere
- Use the same WinSW configuration as pilot agents
- Label each appropriately (e.g., `windows`, `build`, `deploy`)
- Verify all agents appear online

---

## 2️⃣ Expand Job Import

Use **Job Import Plugin** again to migrate more jobs, in small batches.

Recommendations:
- 5–10 jobs per batch
- Verify each job’s required credentials exist
- Disable automatic triggers until all jobs in a batch succeed

---

## 3️⃣ Enable SCM & Webhooks (after stable)

Once jobs run consistently:
- Re-enable SCM polling or webhook triggers
- Monitor for concurrent job execution and load balancing

---

## 4️⃣ Monitoring & Maintenance

Check:
- Jenkins controller heap (<80%)
- SMB PVC usage (`df -h /var/jenkins_home`)
- Agent reconnect stability
- Pod restarts (`kubectl -n jenkins get pods`)

---

## Validation Checklist

- [ ] New agents online and labeled correctly
- [ ] Imported jobs build successfully
- [ ] Webhooks and triggers re-enabled without duplication
- [ ] Controller stable under concurrent load
