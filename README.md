# EKS GitOps — Beginner's Guide

A simple, end-to-end learning project: a 3-tier app (static frontend → Node.js API →
Postgres) deployed on **Amazon EKS**, provisioned with **Terraform**, packaged with
**Helm**, deployed via **GitOps with ArgoCD**, exposed through a single **NGINX ingress
controller**, built by **GitHub Actions**, and observed with **Prometheus + Grafana**.

This guide assumes you've never used most of these tools before, so every command is
explained, not just listed. Commands are given in **PowerShell** (Windows) with bash
notes where it matters.

---

## Table of contents

1. [Concepts, explained in plain English](#1-concepts-explained-in-plain-english)
2. [Prerequisites](#2-prerequisites)
3. [Step 1 — Fork, configure, and push to GitHub](#step-1--fork-configure-and-push-to-github)
4. [Step 2 — Provision the EKS cluster with Terraform](#step-2--provision-the-eks-cluster-with-terraform)
5. [Step 3 — Connect kubectl to your cluster](#step-3--connect-kubectl-to-your-cluster)
6. [Step 4 — Install the NGINX ingress controller](#step-4--install-the-nginx-ingress-controller)
7. [Step 5 — Install Prometheus + Grafana](#step-5--install-prometheus--grafana)
8. [Step 6 — Install ArgoCD](#step-6--install-argocd)
9. [Step 7 — Point ArgoCD at this repo](#step-7--point-argocd-at-this-repo)
10. [Step 8 — Trigger CI/CD by pushing a code change](#step-8--trigger-cicd-by-pushing-a-code-change)
11. [Accessing everything: local vs public endpoint](#accessing-everything-local-vs-public-endpoint)
12. [Troubleshooting](#troubleshooting-real-issues-and-fixes)
13. [Cleanup](#cleanup)
14. [Where to go from here](#where-to-go-from-here)

---

## 1. Concepts, explained in plain English

You don't need to memorize this section — skim it once, then refer back when a term
comes up later.

**Amazon EKS (Elastic Kubernetes Service)** is AWS's managed Kubernetes. Kubernetes
itself is a system for running containers (your app, packaged with everything it needs)
across a group of machines, automatically restarting them if they crash, and routing
traffic to healthy ones. "Managed" means AWS runs the hardest part — the **control
plane** (the brain that makes scheduling decisions) — so you only manage the worker
machines.

**Node group** = the actual EC2 virtual machines ("nodes") that your containers run on.
Terraform creates a "managed node group" of 2 `t3.medium` instances for you. Kubernetes
decides which node each container lands on; you don't pick manually.

**Terraform** is infrastructure-as-code: instead of clicking around the AWS Console, you
describe what you want (a VPC, an EKS cluster, etc.) in `.tf` files, and Terraform
figures out the AWS API calls to create it. `terraform apply` is the command that
actually builds it.

**Pod** = the smallest deployable unit in Kubernetes — one or more containers running
together. **Deployment** = a controller that keeps a set number of identical Pods
running (used here for the stateless frontend and backend). **StatefulSet** = like a
Deployment, but for things that need stable identity and storage — used here for
Postgres, since a database needs its data to survive Pod restarts.

**Service** = a stable network address for a set of Pods (Pods themselves get
recreated with new IPs constantly, so you never talk to a Pod directly). A `ClusterIP`
Service is only reachable inside the cluster; a `LoadBalancer` Service asks AWS to
provision a real internet-facing load balancer for it — **this project deliberately
uses only one of these** (see next paragraph) and routes everything else through it.

**Ingress / Ingress Controller** — an Ingress is a set of HTTP routing rules ("send
requests for `app.example.com` to the frontend, `grafana.example.com` to Grafana,
`argocd.example.com` to ArgoCD"). It does nothing by itself; you need an **Ingress
Controller** (we install NGINX's) actually running in the cluster to read those rules
and act as the real traffic router. Crucially, **one Ingress Controller — and the one
`LoadBalancer` it creates — can serve an unlimited number of Ingress rules and
hostnames.** That's why this project only ever provisions a single AWS load balancer:
Grafana and ArgoCD each get their own `Ingress` object pointing at the same shared
controller, instead of each getting a dedicated `LoadBalancer` Service (which would mean
paying for three separate load balancers).

**Helm** = a package manager for Kubernetes, the same idea as `apt` or `npm` but for
k8s applications. A **chart** is a package (e.g. "kube-prometheus-stack" bundles
Prometheus + Grafana + all the glue between them into one installable unit). A
**release** is one installed instance of a chart, with a name you choose. A **values
file** (`-f some-values.yaml`) overrides the chart's defaults. So the pattern
`helm install <release-name> <chart-name> -f values.yaml` means: "install this package,
call it \<release-name\>, and apply my customizations from values.yaml."

**ArgoCD / GitOps** — instead of you running `kubectl apply` by hand, ArgoCD is a
controller that lives inside your cluster, constantly compares "what's in this GitHub
repo's `k8s/` folder" against "what's actually running," and automatically applies any
difference. Git becomes the single source of truth — if you want to change something,
you commit it to git, you don't touch the cluster directly. Note that ArgoCD only
manages what's under `k8s/` in this repo (the app itself); Grafana and ArgoCD's own
Ingress rules live outside that folder in `ingress-extras/`, since they belong to
separately Helm-installed tools, not the GitOps-managed app.

**Prometheus** = a monitoring system that periodically "scrapes" (pulls) metrics from
your apps and cluster over HTTP. **Grafana** = a dashboard tool that queries Prometheus
and draws graphs. A **ServiceMonitor** is a small object that tells Prometheus "here's
another thing to scrape" — it's how our custom backend app gets picked up automatically
without editing Prometheus's own config.

**GitHub Actions** = CI (Continuous Integration) that runs on GitHub's servers whenever
you push code. Here, it builds a Docker image and pushes it to GHCR (GitHub's container
registry), then commits the new image tag back into `k8s/`. ArgoCD then picks up that
git commit and deploys it — this "CI builds, ArgoCD deploys" split is the standard
GitOps pattern.

---

## 2. Prerequisites

Install these locally before you start:

- an AWS account with credentials configured (`aws configure`)
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.8
- [Git](https://git-scm.com/downloads)
- A GitHub account and an **empty repository** you've created (e.g. `eks-gitops`)

> **Cost note:** this creates a real EKS cluster, 2 worker nodes, a NAT gateway, and
> **one** public load balancer (shared by the app, Grafana, and ArgoCD). Expect roughly
> $6-9/day. Follow the [cleanup](#cleanup) steps when you're done.

> **A note on PowerShell:** PowerShell does not understand a backslash (`\`) at the end
> of a line as "continue on the next line" the way bash does — it'll throw confusing
> parser errors. Every multi-line command below uses PowerShell's actual line-
> continuation character, the backtick (`` ` ``). If you'd rather not deal with this at
> all, every command also works fine typed as one single line.

---

## Step 1 — Fork, configure, and push to GitHub

This project only works once it's an actual git repo that ArgoCD can point at — a local
folder on your laptop is invisible to ArgoCD.

```powershell
cd path\to\eks-gitops

git init
git add .
git commit -m "initial commit"
git branch -M main
git remote add origin https://github.com/<your-username>/eks-gitops.git
git push -u origin main
```

Now replace the `YOUR_GITHUB_ORG` placeholder that appears in a few files
(`k8s/backend/deployment.yaml`, `k8s/frontend/deployment.yaml`,
`argocd/application.yaml`) with your actual GitHub username. Do it automatically:

```powershell
.\scripts\configure.ps1 -GitHubOrg "<your-username>"
```

(bash/Mac/Linux equivalent: `./scripts/configure.sh <your-username>`)

Then commit and push that change:

```powershell
git add .
git commit -m "chore: set github org"
git push
```

Lastly, on GitHub go to **Settings → Actions → General → Workflow permissions** and
select **"Read and write permissions."** This lets the CI workflow push image-tag
updates back into your repo — without it, Step 8 will fail silently.

---

## Step 2 — Provision the EKS cluster with Terraform

```powershell
cd terraform
terraform init
terraform plan
terraform apply
```

`terraform init` downloads the AWS provider and the VPC/EKS modules this project uses.
`terraform plan` shows you what it *would* create, as a dry run. `terraform apply` (type
`yes` when prompted) actually creates it. This takes **12-18 minutes** — the EKS control
plane is genuinely slow to provision, that's normal. By default this builds an EKS
**1.36** cluster (the latest available version as of mid-2026) — change
`terraform/variables.tf` if you need an older version.

When it finishes, Terraform prints several outputs, including a ready-to-run command:

```powershell
terraform output configure_kubectl
```

---

## Step 3 — Connect kubectl to your cluster

Run the command Step 2 printed, e.g.:

```powershell
aws eks update-kubeconfig --region us-east-1 --name eks-gitops
```

This writes connection details into `~/.kube/config` so `kubectl` knows which cluster
to talk to. Verify:

```powershell
kubectl get nodes
```

You should see 2 nodes in `Ready` status. **If you instead get an authentication error
here, jump to [Troubleshooting](#troubleshooting-real-issues-and-fixes) — it's a known
one-command fix.**

---

## Step 4 — Install the NGINX ingress controller

This is the **one and only** component in this project that provisions an AWS load
balancer. Everything else (Grafana, ArgoCD, the app) routes through it via `Ingress`
rules.

```powershell
helm repo add ingress-nginx 
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx --create-namespace `
  -f helm-values/ingress-nginx-values.yaml
```

`helm repo add` registers where to download the chart from (this only needs doing once
per machine). `helm install` then does the actual install — creating the
`ingress-nginx` namespace, and requesting a public AWS load balancer (because our
values file sets `service.type: LoadBalancer`).

Confirm it's up and check its public address:

```powershell
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

The `EXTERNAL-IP` column will show `<pending>` for a minute or two, then populate with
an ELB hostname. **Save this hostname** — you'll point every hostname (app, Grafana,
ArgoCD) at it in [Accessing everything](#accessing-everything-local-vs-public-endpoint).

---

## Step 5 — Install Prometheus + Grafana

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
  --namespace monitoring --create-namespace `
  -f helm-values/kube-prometheus-stack-values.yaml
```

This one chart installs Prometheus, Grafana, Alertmanager (disabled in our values file
to keep things simple), and the `ServiceMonitor` custom resource type — which is what
lets our backend app opt into monitoring later just by existing (see
`k8s/backend/servicemonitor.yaml`). Our values file keeps Grafana's own Service as
`ClusterIP` — it's reached through the shared ingress controller instead, via the
`Ingress` object below.

Route Grafana through the shared load balancer:

```powershell
kubectl apply -f ingress-extras/grafana-ingress.yaml
```

---

## Step 6 — Install ArgoCD

```powershell
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd `
  --namespace argocd --create-namespace `
  -f helm-values/argocd-values.yaml
```

Same pattern again — our values file keeps ArgoCD's Service as `ClusterIP` too, and
tells the ArgoCD server to serve plain HTTP (`--insecure`) instead of its default
self-signed HTTPS, so the shared ingress controller can proxy it cleanly. Route it
through the load balancer:

```powershell
kubectl apply -f ingress-extras/argocd-ingress.yaml
```

Fetch the initial admin password (PowerShell doesn't have `base64 -d` like bash does,
so this uses .NET's decoder instead):

```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" |
  ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

Username is `admin`. See [Accessing everything](#accessing-everything-local-vs-public-endpoint)
for how to reach the login page itself.

---

## Step 7 — Point ArgoCD at this repo

```powershell
kubectl apply -f argocd/application.yaml
```

This creates an `Application` object — ArgoCD's instruction to "watch this repo's `k8s/`
folder and keep the cluster in sync with it." Watch it work:

```powershell
kubectl -n argocd get applications
kubectl -n app get pods
```

Within a minute or two you should see `postgres-0`, two `backend-xxxxx` pods, and two
`frontend-xxxxx` pods, all `Running`. If pods show `InvalidImageName` at this point,
that's expected and gets fixed in the next step.

---

## Step 8 — Trigger CI/CD by pushing a code change

The backend and frontend Deployments reference images that don't exist yet — they only
get built once GitHub Actions runs, which only happens on a push that touches
`app/backend/**` or `app/frontend/**`. Make any small change (or just re-save a file)
and push:

```powershell
git add .
git commit -m "trigger initial build"
git push
```

This triggers `.github/workflows/ci-backend.yaml` and `ci-frontend.yaml`, each of which:
1. builds a Docker image
2. pushes it to `ghcr.io/<you>/eks-gitops-backend:<commit-sha>`
3. rewrites the image tag inside `k8s/backend/deployment.yaml`
4. commits and pushes that change back to `main`

ArgoCD notices the new commit (polls every ~3 min by default, or click "Refresh" in its
UI) and rolls the new image out — no manual deploy step, ever, from here on.

One extra check the first time: newly-created GHCR packages default to **private** —
Pods in your cluster won't be able to pull a private image without extra credentials.
Go to your GitHub profile → **Packages** → the new package → **Package settings** →
change visibility to **Public**.

---

## Accessing everything: local vs. public endpoint

There are always two ways to reach anything here: **locally** via `kubectl
port-forward` (traffic tunnels through your kubectl connection, nothing touches the
internet, works even before any DNS is set up), or **publicly** through the single
ingress-nginx load balancer, using hostnames.

### Set up the hostnames once

Get the shared load balancer's address:

```powershell
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
```

For real browser access to any of the three hostnames below (`app.example.com`,
`grafana.example.com`, `argocd.example.com`), either:
- point real DNS records at that ELB hostname, or
- add lines to your hosts file (`C:\Windows\System32\drivers\etc\hosts`, edited as
  Administrator) mapping each hostname to the ELB's IP address, or
- skip DNS entirely and pass a `Host` header manually with `curl` (shown below) — good
  enough to confirm things are working without touching your hosts file.

### The app itself

**Local:**
```powershell
kubectl -n app port-forward svc/frontend 8080:80
```
Open `http://localhost:8080`

**Public:**
```powershell
curl -H "Host: app.example.com" http://<ELB-hostname>/
```
or browse to `http://app.example.com` once DNS/hosts-file is set up.

### Grafana

**Local:**
```powershell
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```
Open `http://localhost:3000` — login `admin` / `admin123` (change it after first login).

**Public:**
```powershell
curl -H "Host: grafana.example.com" http://<ELB-hostname>/
```
or browse to `http://grafana.example.com` once DNS/hosts-file is set up.

### ArgoCD

**Local:**
```powershell
kubectl -n argocd port-forward svc/argocd-server 8080:80
```
Open `http://localhost:8080` (plain HTTP — recall we set `--insecure` in Step 6).

**Public:**
```powershell
curl -H "Host: argocd.example.com" http://<ELB-hostname>/
```
or browse to `http://argocd.example.com` once DNS/hosts-file is set up.

> Note: the `argocd` CLI tool (as opposed to the web UI) talks gRPC and needs either
> `argocd login --plaintext` against a port-forward, or a second, gRPC-aware Ingress —
> out of scope for this guide, but worth knowing if `argocd login argocd.example.com`
> from the CLI doesn't behave like the browser does.

---

## Troubleshooting: real issues and fixes

These are the actual problems most people hit, in the order they tend to show up.

**`kubectl get nodes` fails with `the server has asked for the client to provide
credentials`, even though `aws sts get-caller-identity` works fine.**
This means AWS-level credentials are valid, but that IAM identity was never granted
permission to talk to the Kubernetes API itself. Fix it directly:
```powershell
aws eks create-access-entry --cluster-name eks-gitops --region us-east-1 --principal-arn <your-IAM-user-or-role-ARN> --type STANDARD
aws eks associate-access-policy --cluster-name eks-gitops --region us-east-1 --principal-arn <your-IAM-user-or-role-ARN> --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster
```
Get your ARN from `aws sts get-caller-identity`. (This project's Terraform already sets
`enable_cluster_creator_admin_permissions = true`, which grants this automatically to
whoever runs `terraform apply` — this fix is only needed for a *second* person/identity,
e.g. if you access the AWS Console with a different login than the CLI used.)

**Any multi-line command throws `Missing expression after unary operator '--'` or
`unexpected arguments: \`.**
You pasted a bash-style command (using `\` line continuation) into PowerShell.
PowerShell needs a backtick (`` ` ``) instead, or just put the whole command on one line.

**`helm install ... -f helm-values/xxx.yaml` fails with `The system cannot find the
path specified`.**
You're not in the project root. `cd` back to the folder containing `helm-values/`,
`k8s/`, `terraform/`, etc., or adjust the path to match where you're standing.

**ArgoCD shows `Synced` and `Healthy`, but `kubectl -n app get pods` (or `get all`)
returns nothing.**
Almost always means `directory.recurse: true` is missing from `argocd/application.yaml`
— without it, ArgoCD only applies files directly inside `k8s/` and silently skips
everything in subfolders (`k8s/database/`, `k8s/backend/`, `k8s/frontend/`), while still
reporting a "healthy" sync of the few files it did find. This repo's
`argocd/application.yaml` already includes it — if you're hitting this, check you copied
the file correctly and re-apply:
```powershell
kubectl apply -f argocd/application.yaml
```

**Pods stuck in `InvalidImageName`.**
The `YOUR_GITHUB_ORG` placeholder wasn't replaced in `k8s/backend/deployment.yaml` /
`k8s/frontend/deployment.yaml`. Run `scripts/configure.ps1` (see Step 1), commit, push.

**Pods move from `InvalidImageName` to `ImagePullBackOff`.**
Expected in-between state: the placeholder is now fixed, but the image doesn't exist in
GHCR yet because CI hasn't run. Do Step 8 (push any change) to trigger the build, and
make sure the resulting GHCR package is set to **Public** (see the note at the end of
Step 8) — a private package will also cause this error even after a successful build.

**ArgoCD login says `Invalid username or password`.**
Almost always a copy-paste artifact (stray newline) from manually selecting terminal
output. Pipe the decoded password straight to your clipboard instead:
```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" |
  ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) } |
  Set-Clipboard
```
Then `Ctrl+V` directly into the password field.

**Grafana or ArgoCD's Ingress returns a 404 from nginx.**
Usually means the `Host` header didn't match — double-check you're either using `curl -H
"Host: ..."` exactly as shown, or that your hosts-file entry / DNS record is spelled
identically to the `host:` field in `ingress-extras/grafana-ingress.yaml` or
`argocd-ingress.yaml`.

**`postgres-0` stuck in `Pending`.**
Almost always the EBS CSI driver / `gp3` StorageClass. Check:
```powershell
kubectl -n app describe pod postgres-0
```
and look at the Events at the bottom for a volume-provisioning error.

---

## Cleanup

Order matters — remove the ingress controller (and therefore the load balancer) *before*
destroying the VPC, or Terraform will fail to delete a VPC that still has an ELB
attached to it.

```powershell
kubectl delete -f ingress-extras/grafana-ingress.yaml
kubectl delete -f ingress-extras/argocd-ingress.yaml

helm uninstall ingress-nginx -n ingress-nginx
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall argocd -n argocd

cd terraform
terraform destroy
```

---

## Where to go from here

- Swap the in-cluster Postgres for Amazon RDS and connect via a `Secret` populated from
  AWS Secrets Manager (via the External Secrets Operator).
- Add a staging/prod split using ArgoCD's "app of apps" pattern or Kustomize overlays.
- Put the shared load balancer behind ACM + HTTPS via `cert-manager`, and drop
  `--insecure` from the ArgoCD values once you have real TLS terminating at the ingress.
- Add Horizontal Pod Autoscalers driven by the Prometheus metrics you're already
  collecting.
- Move Terraform state to an S3 backend with DynamoDB locking (see the commented-out
  block in `terraform/providers.tf`) once more than one person touches this.
