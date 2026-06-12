# Runbook: `KubePodCrashLooping` — event-ingestion 


| | |
|---|---|
| Service | `event-ingestion` (ns `ingest`) |
| Owner | `#team-ingestion`, PagerDuty `ingestion-oncall` |
| Downstream | Kafka `events.raw` (`kafka-prod`) |
| Metrics | Grafana → "Ingestion / Overview" |
| Logs | Grafana → Loki, `{namespace="ingest", app="event-ingestion"}` |

---

## 1. Triage (≤5 min, in order)

1. **Real or flap?** Dashboard → is the SLO burn-rate alert firing? If green again, watch 10 mins for stability.
2. **Blast radius:** `kubectl -n ingest get pods -l app=event-ingestion` → all down = full outage (escalate now).
3. **What changed?** `kubectl -n ingest rollout history deploy/event-ingestion` + check Argo CD / deploy events for a sync in last ~30 min. Config/secret/infra change?
4. **Why dying?** `kubectl -n ingest describe pod <pod>` (events, exit code) + `kubectl -n ingest logs <pod> --previous`:

   | Signal | Cause | Action |
   |---|---|---|
   | `OOMKilled` | mem limit / leak | scale-out / raise limit |
   | startup config/secret error | bad config / rotated secret | rollback or hotfix |
   | can't connect to Kafka | downstream | escalate to platform team |


## 2. Decision tree

```
Deploy/config change correlates?
├─ YES → ROLLBACK (default — fast, reversible)
└─ NO
   ├─ OOMKilled / saturated, no code bug → SCALE OUT / raise limits
   ├─ Kafka/dependency is the cause      → ESCALATE to owner (don't touch app)
   └─ known bad config, no good rollback → HOTFIX
```

> **Argo CD manages this app.** Any live `kubectl` change is reverted on the next sync. So either go through Git, or pause sync for an emergency override and land the fix in Git after.

**Preferred — via Git/Argo (no pause needed):**
```
# Rollback: roll back to the previous healthy revision
argocd app rollback event-ingestion <prev-revision>     # or pin to last-good commit, Argo syncs

# Increase replicas or memory requests and limits on github Application resource and push the commit.
```

**Emergency override — when you can't wait for a PR:**
```
argocd app set event-ingestion --sync-policy none        # pause auto-sync FIRST

kubectl -n ingest scale deploy/event-ingestion --replicas=<n>     # scale, OR
kubectl -n ingest patch deploy/event-ingestion --type=json \      # raise mem limit
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"2Gi"},
       {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"2Gi"}]'
kubectl -n ingest rollout status deploy/event-ingestion

# AFTER recovery: commit the change to Git, then re-enable sync
argocd app set event-ingestion --sync-policy automated
```

**Verify recovery:** pods Ready + burn-rate alert clears + **`events.raw` lag draining** (events flowing, not just pods green).

## 3. Escalate when

- Full outage / fast-burn SLO, or cause is a dependency you don't own, or rollback didn't recover in ~15 min, or you're unsure.
- Path: service owner → Kafka/platform on-call → declare incident + page IC if sustained customer impact.

Use this to notify stakeholders:

**Internal (every 15–30 min):**
> [INC-xxxx] Service:event-ingestion crashlooping — INVESTIGATING/IDENTIFIED/MONITORING
> Impact: campaign event messages are getting delayed/dropped, message count rising. Started <…>. Cause: <…>. Action: <…>. IC: <…>.

**Customer-facing (only once impact confirmed, no internals):**
> Investigating delays processing inbound campaign events since <time> UTC. Events are queued, none lost. Next update by <time>.

## 4. Post-Incident Review captures

PIR should capture the following:
- the whole timeline of the incident.
- root cause and impact.
- Screenshots of metrics, alerts, logs, etc that shows.
- Log of actions performed.
- What fixed.
- Action items with owners.
