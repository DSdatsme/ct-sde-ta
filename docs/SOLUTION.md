

## Section 1: Infrastructure Architecture & IaC

### 1a. Terraform Implementation

#### EKS Module

EKS module is implemented in [infra/modules/eks-cluster/](./infra/modules/eks-cluster/) — see its [README](./infra/modules/eks-cluster/README.md) for inputs, defaults, and usage.

#### VPC Module

VPC module is implemented in [infra/modules/vpc/](./infra/modules/vpc/) — see its [README](./infra/modules/vpc/README.md) for inputs, defaults, and usage.

#### Transit Gateway Module (inter-region connectivity)

TGW module is implemented in [infra/modules/transit-gateway/](./infra/modules/transit-gateway/) — see its [README](./infra/modules/transit-gateway/README.md).

**TGW over peering.** Peering is point-to-point and non-transitive whereas a Transit Gateway is a hub: each VPC attaches once, routing is central, and regions join via a single cross-region TGW attachment link. It scales as we add regions/accounts and gives one place to later add inspection or RAM-shared attachments. The module is regional (creates the TGW + VPC attachments).

**Reconciling with 1c.** This does not contradict the EU residency design. The TGW connects the VPCs that are explicitly specified. EU (`eu-west-1`) is deliberately left unattached, so no peering link at all, with the SCP/RCP from 1c as an additional restriction control. So we build inter-region connectivity where it's allowed.


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
Same with infra creation. All the infra gets created through the same Github Workflows.

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
We will also setup AWS plugin on Grafana to get some AWS specific visualizations if needed.

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

## Section 3: Developer Platform, CI/CD & Engineering Velocity

### 3a. CI/CD Pipeline

We are assuming the microservice to be deployed on EKS is `event-ingestion`. 
Desired state is one directory per environment (`envs/staging/`, `envs/prod/`), so promotion is just a tag bump in the app's env folder.

- **PR stage** → [.github/workflows/pr.yml](../.github/workflows/pr.yml): lint → unit tests → Code Scaning (Trivy fs) → build image → Trivy image scan → push to ECR, tagged with the PR head commit SHA. The image is scanned before push, so a HIGH/CRITICAL finding fails the PR and a vulnerable image never reaches the registry. AWS auth uses GitHub OIDC, so no static IAM keys.
If you want a real live example: `https://github.com/DSdatsme/dsdatsme-sample-nodejs-app/blob/main/.github/workflows/build.yml`

- **Staging stage** → [.github/workflows/staging.yml](../.github/workflows/staging.yml): runs on PR merge, and bumps `envs/staging/.../values.yaml` to the PR head SHA — i.e. the exact image the PR already built, scanned, and pushed. This is deliberate **build-once**: we promote the tested artifact rather than rebuilding on main. Branch protection requires "branches up to date before merge", so the head commit was tested against current main.
Argo CD's staging app then syncs, staging is ungated for fast feedback, and smoke tests run against it.

- **Production gate:** promotion to prod is a PR that bumps `envs/prod/` to the staging-validated SHA. Branch protection on the GitOps repo (required review + status checks) *is* the manual approval gate so no GitHub Environment job is needed, because Argo does the deploy, not Actions. Merge → Argo prod app syncs → canary below.


**Production — canary via Argo Rollouts**

Merging the prod bump, Argo CD syncs an Argo Rollout. The canary steps 5 → 10 → 50 → 100% with a pause and an automated analysis at each step:

```yaml
strategy:
  canary:
    maxSurge: 1
    maxUnavailable: 0
    steps:
      - setWeight: 5
      - pause:
          duration: 5m
      - setWeight: 10
      - pause:
          duration: 5m
      - analysis:
        templates:
        - templateName: success-rate-latency
      - setWeight: 50
      - pause:
        duration: 10m
      - analysis:
        templates:
        - templateName: success-rate-latency
      - setWeight: 100
```

The `AnalysisTemplate` queries Prometheus for the service's SLIs like defined in Section 2a.

Automated rollback is the default: if the metric breaches its threshold during any step, the analysis fails, the Rollout aborts and shifts 100% of traffic back to the stable version so no human needed. We page only after an auto-abort, not to ask permission to roll back.

**Secret management — none in YAML**

Secrets are injected at runtime, never committed. The External Secrets Operator runs in-cluster and syncs from AWS Secrets Manager into native K8s Secrets; the manifests only reference a secret name, not its value. ESO's service account reads Secrets Manager via IRSA, scoped to this service's secret path.

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: { name: event-ingestion, namespace: ingest }
spec:
  secretStoreRef: { name: aws-secrets-manager, kind: ClusterSecretStore }
  target: { name: event-ingestion }      # the K8s Secret ESO creates
  data:
    - secretKey: kafka_sasl_password
      remoteRef: { key: prod/ingest/event-ingestion, property: kafka_sasl_password }
```

So a leaked repo or pipeline log exposes no secrets.

### 3b. Self-Serve Environments using IDP

This IDP portal will allow them to configure the environment parameters and the values are injected into the Terraform templates.
DevOps team can help them get some golden templates which are full of guardrails and focused.

- Speed: they just have to fill or update the values on portal. Behind the scene it will template the terraform and will create a PR for the same. after reviewing the plan by LLM, it will be merged and auto deployed on staging or dev environment
- Cost: Since these templates are bounded, the costs will be in control. Their resources would be well labeled.
- Security: These environments would be created in dev account, so it would be isolated from production or any other account.
- Cleanup: These envs would have a TTL and we will run a terraform destroy based on it. If they need it for longer, they can extend it or else it will be cleaned up.

## Section 4: Cost Engineering

### 4a. 90-Day Cost Reduction Plan

So the goal is to save approx. $105–126K/mo but since no billing access given it's hard to assume the cost breakdown. So we will start with quick wins and will move towards complex and architectural changes.



**Quick wins (week 1–2)** — ordered by impact; all low-effort, low-risk, no SLA exposure.

| Initiative | Est. savings | Effort | Risk |
|---|---|---|---|
| turn off non-prod envs outside business hours | ~$15K | Low | Low |
| Setup VPC endpoints (S3, ECR, etc.) to cut NAT data-processing + transfer | ~$10K | Low | Low |
| Do resource cleanups - Delete idle/un-attached EBS, old snapshots, unused EIPs, idle ALBs, EC2s etc | ~$10K | Low | Low |
| Setup S3 lifecycle + Intelligent-Tiering on old/cold objects | ~$8K | Low | Low |

Setup kubecost so data is available in the following week.

**Medium-term (month 1–2)** — right-sizing + calculate commitments.

| Initiative | Est. savings | Effort | Risk |
|---|---|---|---|
| Check utilization and rightsize resources (EKS, RDS, ElastiCache etc) | ~$50K | Med | Low |
| Savings Plans (EC2 Instance + Compute) on the steady compute baseline (1-yr) | ~$40K | Low | Low |
| Reserved Instances for RDS + ElastiCache baseline (1-yr) | ~$15K | Low | Low |


*Savings Plans vs RIs — when each:* 
We will first check the RI and savings plans charts and analyze the trends after the right sizing. for two weeks. based on it we will decide to go with RI or Savings Plans. 

For EKS-EC2: the steady ~70% of capacity goes on 1-year no-upfront **EC2 Instance Savings Plans** (instance-family locked, so the deepest discount), and the remaining ~30% + bursty usage on **Compute Savings Plans** (flexible across family/region). We use Savings Plans for EC2, not RIs — Savings Plans replaced them for compute.

For RDS and ElastiCache, the prod + staging baseline goes on RIs (Savings Plans don't cover these) — stable and predictable, so 1-year, no upfront.

For other services that just do data processing etc would live on spot instance for most. So only 10-30% of EC2 consumption would be over RI+Savings Plans commitment. Which would be ideal.

**Architectural (month 2–3)** — structural changes.

| Initiative | Est. savings | Effort | Risk |
|---|---|---|---|
| Move to ARM based EKS nodes + RDS/ElastiCache | ~$25K | Med–High | Low–Med |
| Cut inter-region transfer: regional read replicas/caches, async + compressed cross-region | ~$20K | High | Med |
| Add spot instance node pools for specific services | ~$15K | Med | Med |
| Adopt Karpenter for active node consolidation (supersedes Cluster Autoscaler) | ~$30K | Med | High |

Karpenter bin-packs workloads and terminates underutilized nodes, this is a bigger lever than autoscaler's scale-down (which only removes empty nodes). The risk is higher because consolidation evicts and reschedules running pods, so it needs PDBs and `do-not-disrupt` annotations before rollout.

### 4b. FinOps Process Design

Cutting the bill once is easy; keeping it cut needs teams to see and *own* their spend trends.

**Making it mandatory to tag each and every cloud resource**

A small, required set of keys on everything: `created_by`, `team`, `service`, `environment`, `project`, `purpose`, so they're never missing:

- **In code:** every Terraform module sets these via `default_tags`, so anything provisioned the right way is tagged by construction.
- **Preventive guardrail:** an SCP/IAM policy with an `aws:RequestTag`/`aws:TagKeys` condition denies resource creation when the required tags are missing, so untagged resources can't be created in the first place, even outside Terraform.
- **At the org:** AWS Tag Policies flag non-compliant resources, and we backfill the existing click-ops resources once, up front.
- **Automated reports (backstop):** a script runs daily, finds resources that don't comply with the tagging convention, and emails the list for review.

**Showback first, chargeback later**

Start with **showback** i.e. every team gets a dashboard of their spend and a weekly report. Visibility alone changes behaviour, and it builds trust in the numbers without finance friction. Once tags are trustworthy and teams trust the breakdown, move to **chargeback**, where the spend actually lands on the team's budget.

For the shared resources like EKS, basic AWS level resource tagging is not enough. Kubecost will track costs by namespace/label/pod, and that allocation feeds the same per-team report. 

**Alerting**

- **AWS Budgets** per team/cost-center, alerting at 80%, 100%, and *forecasted* to exceed routed to the owning team's Slack. The team that can act is the team that gets paged.
- **Anomaly Detection** alerts are also needed so that teams can check if there are sudden spikes in costs for any resource so they can act promptly.
