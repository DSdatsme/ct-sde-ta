

## Section 1: Infrastructure Architecture & IaC

### 1a. Terraform Implementation

#### EKS Module

EKS module is implemented in [infra/modules/eks-cluster/](./infra/modules/eks-cluster/) — see its [README](./infra/modules/eks-cluster/README.md) for inputs, defaults, and usage.

#### VPC Module

VPC module is implemented in [infra/modules/vpc/](./infra/modules/vpc/) — see its [README](./infra/modules/vpc/README.md) for inputs, defaults, and usage.


### 1b State & Drift Management

Remote state in S3 with a DynamoDB lock table. The state is stored based on account, region, and layer and the folder structure mirrors it 1:1, so where state lives is always obvious from where you're standing:

```
<account-bucket>/<env>/<region>/<layer>/terraform.tfstate
  devbucket/dev-team-a/eu-west-1/network/terraform.tfstate    # VPC, subnets, TGW
  devbucket/dev-team-a/eu-west-1/platform/terraform.tfstate   # EKS, addons
  prodbucket/prod/eu-west-1/network/terraform.tfstate
```

**Across accounts (dev, staging, prod)**

One state bucket + DynamoDB lock table per account tier, living in that account. Prod state sits in the prod account, so a leaked dev credential can't read or corrupt it and a bad apply stops at the account boundary. Buckets have versioning on (roll back a corrupted state), SSE-KMS, public access blocked, and cross-region replication for SOC 2 / DR.

**Across regions**

Region is a real directory and a real state key segment, not a workspace flag:

```
live/
  prod/
    eu-west-1/
      network/      # → state key prod/eu-west-1/network
      platform/
    us-east-1/
      network/
      platform/
modules/
  vpc/
  eks-cluster/
```

Each leaf (`live/<env>/<region>/<layer>/`) is a thin root: a backend block keyed to its own path, a call to the shared module in `modules/`, and a region-specific tfvars (CIDRs, AZs). I'd keep regions as explicit directories rather than one parameterized root. This is because we want to keep plan and apply lighter and also provide isolation based on region. It also fits the 1c residency rule: EU is literally its own folder, state, and account, nothing shared to leak across regions.

**Across teams on one codebase**

This is also why state is split by *layer* within an env, not one mega-state. A single root = one backend = one state file. One-state-per-env means every plan touches everything, it's slow, and one lock blocks everyone; one-state-per-resource is too granular. Grouping by layer (network / platform / data) lets the platform team own the slow-changing network while app teams iterate on the cluster — separate state, separate lock, no contention. Cross-layer refs (EKS needs the VPC's subnet IDs) go through `terraform_remote_state` or data-source lookups by tag.

Modules live in one repo; environments consume pinned versions. `CODEOWNERS` gates the modules so the platform team reviews changes there, while app teams own their env configs. Nothing applies from a laptop: a plan runs on every PR and posts the diff, apply only runs after merge from CI with the per-account role. That leaves a reviewable record of who changed what.

So if a team wants to have their own customization, we also provide them access to their own folder like prod/us-east-1/app-team-lambda/. This way we can have isolation and the team can have their own customization. It reduces the cognitive load on the team and provides them full autonomy over their infrastructure.

**Drift detection**

A scheduled CI job (nightly) runs `terraform plan -detailed-exitcode` across every state. Exit code 2 means the live infra no longer matches code, so the job fails and alerts Slack with the offending component. `driftctl` runs alongside it to catch resources created out-of-band that Terraform doesn't even track (someone clicking in the console), which a plan won't surface.

**Remediation**

Two cases. If the change shouldn't exist, re-apply to put things back. If it's a legitimate change someone made by hand, codify it, bring it into Terraform (`import` if it's a brand-new resource) and merge, so the next plan comes back clean. Either way the rule is the same: code is the source of truth, drift gets resolved one way or the other, it doesn't sit.

### 1c Design Question

The constraint is hard: EU customer data stays in `eu-west-1` and never leaves. The thing we still want shared is *how we deploy* so that we can make sure consistency across the organization but not the data, not the runtime.

**Isolation, not federation**

EU gets its own AWS account and its own EKS cluster in `eu-west-1`. No cross-region cluster federation, no shared data plane, federation would mean control traffic, and potentially data, crossing regions, which is exactly what we're avoiding. Each region is a self-contained stack (own VPC, cluster, state, backups). Data physically can't leave because nothing is wired to carry it out.

**One control plane for deployments**

"Single control plane" here is deployment control. We run Argo CD as the deployment tool pointed at every regional cluster. A change merges once in Git, Argo syncs it to the EU cluster and the US cluster from the same definitions. Engineers ship from one place, the clusters stay regionally isolated. Argo pushes manifests, it doesn't move customer data.
Same with infra creation. All the infra gets created thorugh the same Github Workflows.

**IAM boundary**

Defense in depth, layered from the org down to the workload, so the EU account can't reach non-EU regions and EU data can't be read from outside, by accident or otherwise:

- **SCP (org/OU level, principal-side)** denies any action outside the allowed EU regions for the EU account, via an `aws:RequestedRegion` condition. This is the hard wall, even an admin in that account can't create resources elsewhere.
- **RCP (org level, resource-side)** locks the other direction: deny access to EU resources (S3 buckets, KMS keys) for any principal outside our org or the region. The SCP stops our own identities leaking out, the RCP stops external or cross-account identities reaching in. AWS frames using both together as a data perimeter.
- **Region deactivation (account level)**, the EU account has all non-EU regions turned off, so they aren't even reachable. Belt-and-suspenders behind the SCP.
- **Permission boundaries** on the roles CI assumes, so a pipeline targeting EU is scoped to EU regions only. IRSA roles for EU workloads are region-scoped the same way.

**CI/CD enforcement**

Policy gates in the pipeline (OPA/Conftest) check Terraform plans and Kubernetes manifests before anything applies. A workload tagged as EU data class that points at a non-EU region, bucket, or cross-region replication fails the gate and the PR can't merge. State and pipelines are already per-region (from 1b), so there's no shared path where an EU deploy could land in `us-east-1` by mistake. The SCP is the backstop if a policy check is ever missed.

## Section 2: Reliability, Observability & Incident Response

### 2a. Observability Stack Design

The current infra uses CloudWatch and a self-hosted Prometheus/Grafana for apps, no common alerting. 
I'd standardize on the Grafana+Prometheus+Loki+Tempo stack with OpenTelemetry as the collection layer, and run the managed flavors where the ops cost isn't worth it. I'm deliberately not reaching for Datadog/New Relic because at 30B events/day their per-host/per-event pricing fights the Section 4 mandate to cut 25–30% off the bill, and we already run half of this.
Also I assume, since we already run Prometheus, team already has some experience with this stack, and we already have a Grafana running, so we can reuse the same UI and dashboard concepts.

**The four pillars (one tool each)**

| Pillar | Tool | Why |
|---|---|---|
| Metrics | Prometheus scrape → **Mimir** | Keep what the team already knows; Mimir adds long-term storage on S3 and the per-tenant cardinality limits we need at this scale. |
| Logs | **Loki** | Indexes labels not full text, so storage is cheap object storage; same query language and UI as metrics. |
| Traces | **Tempo** | Object-storage backed, no heavy index; links trace↔logs↔metrics via exemplars. |
| Events | `kube-event-exporter` + deploy events | K8s events and "what changed" land in the same pipeline, so an alert can show the deploy that caused it. |

One Grafana on top for all four. One storage primitive underneath — S3 — for metrics, logs, and traces, lifecycle'd like any other bucket.

**Data flow**

Collection → aggregation → storage → alerting, with a single agent doing collection:

- **Collect:** OpenTelemetry Collector (or Grafana Alloy) as a DaemonSet + gateway. Apps instrument with OTel SDKs. One agent for all three signals instead of a per-tool zoo.
- **Aggregate/store:** Collector forwards to Mimir / Loki / Tempo, all writing to S3.
- **Alert:** Alertmanager (or Grafana Alerting) evaluates rules and routes to PagerDuty for pages and Slack for context.

Standardizing on OTel matters more than any single backend choice, we can instrument once, and swapping a backend later is just a config change.

**Cardinality management (the real problem at 30B/day)**

Cardinality, not raw volume, is what blows up a Prometheus/Mimir bill as every unique label combination is a separate time series. Controls, in order of impact:

- **Drop high-cardinality labels at the collector** before they're stored — `user_id`, `request_id`, raw URLs, pod hashes. These belong on traces/logs, never on metrics.
- **Recording rules** to pre-aggregate the expensive queries dashboards hit repeatedly.
- **Per-tenant ingestion and active-series limits in Mimir**, so one team's bad label can't take down everyone's metrics.
- **Metric/label budgets per team**, surfaced back to them (ties into 4b) — make cardinality a number the owning team sees and owns.

**SLO-based alerting, on an SLI framework teams build on**

The one rule: alert on what the service *does*, not the resources it runs on. SLIs should be tied to the app's purpose. A web service pages on latency/5xx, not CPU: high CPU might cause a problem or might not, and most problems aren't CPU, so the symptom catches everything, the cause catches one thing badly. CPU stays on a dashboard for diagnosis. Same reason we don't alert per-dependency: if the DB is slow the request SLI already degrades, so a separate DB page is the same incident counted twice.

The platform team ships an SLI template per service shape so nobody starts blank, for example a stateless HTTP service → availability + p99 latency; an async consumer → success ratio + consumer lag; a batch job → job success + on-time completion. Teams declare just the SLO target in their repo; the platform generates the burn-rate rules.

So the teams would setup on SLIs that they have come up with by understanding the nature of their app.

### 2b. Runbook & Incident Response

Runbook for the `KubePodCrashLooping` event-ingestion scenario is in [docs/runbooks/kubepodcrashlooping-event-ingestion.md](./docs/runbooks/kubepodcrashlooping-event-ingestion.md) — ordered triage, a rollback/hotfix/scale-out decision tree, escalation + comms templates, and the PIR checklist.

### 2c. Reducing Alert Noise

If an alert auto-resolves in 5 minutes with no human action, it's basically either a flaky check or just a notification. This shows we are unnecessarily paging folks for something that resolves by itself.

The goal is simple: a page should mean "a human needs to act now." Everything else is a dashboard or a ticket.

**Audit** — Get the alert history from Alertmanager/PagerDuty. Based on the alert fire time and close time, we can determine if it was resolved by a human or by itself. Filter the list based on it for further analysis.

**Classify** — tag each rule into a bucket: self-resolving, duplicate, non-actionable, or actionable. Sort by fire count so the noisiest rules get fixed first.

**Remediate** — by bucket:
- Self-resolving (the 60%) -> convert to SLO burn-rate (from 2a). A blip the system absorbs burns no budget, so it never pages; only sustained user-facing harm does. That's the real fix, not just a wider threshold.
- Duplicates -> group/inhibit in Alertmanager (suppress the symptom alerts when the root-cause alert is firing).
- Non-actionable -> If there's no action, it's not a page. Delete the alert rules for those.
- Actionable but no runbook → create a runbook.
- Still noisy -> Improve thresholds or increase the time window based on the observation.

> Rule going forward: every alert must link to an SLO and a runbook, or it doesn't get to page. New paging alerts go through the same review as code.

**Health metrics for the alerting system**

- **Actionability rate** — % of alerts on which some action was taken.
- **Auto-resolve rate** — % clearing with no action. This is what's at 60% today. We should drive it down.
- **Pages per on-call shift** — the fatigue signal.
- **% of alerts tied to an SLO + runbook** — coverage of the rule above.
- **MTTA / MTTR** — are pages even being acted on, and how fast.
- **Top-N noisiest rules** — Get the top N noisy rules and make them actionable or delete them. If needed automate the action to reduce the noise and page fatigue.
