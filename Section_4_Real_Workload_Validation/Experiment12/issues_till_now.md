# Experiment 12 — Issues Log

All issues encountered during implementation, in chronological order.  
Each entry includes: symptom, root cause, fix applied, and files changed.

---

## Issue #1: `source setup-venv.sh` kills terminal on error or Ctrl+C

**Date:** 2026-04-20  
**Step:** Step 0 — Python venv setup  
**Symptom:** After sourcing `setup-venv.sh`, pressing Ctrl+C or encountering any error (even in a later command) would kill the entire terminal session. The user would be dropped to `root@Mighty:/mnt/c/Users/shash/Downloads#` — a different user, different directory.

**Root Cause:** `set -euo pipefail` at the top of a **sourced** script. Unlike `bash script.sh` (which runs in a subshell), `source script.sh` executes directly in the parent shell. So `set -e` modified the user's live shell options — any subsequent error would trigger "exit on error", killing the entire terminal session (not just the script).

**Fix Applied:**
- Removed `set -euo pipefail` entirely from the sourced script
- Added `_svenv_saved_opts=$(set +o)` to save caller's shell options at entry
- Added `eval "$_svenv_saved_opts"` to restore them on exit via `_svenv_cleanup()`
- Replaced `exit 1` with `return 1` on all error paths (sourced scripts must never `exit`)
- Added `trap '_svenv_abort' INT TERM` to intercept Ctrl+C with a friendly message
- Added a guard block that detects non-sourced execution (`bash setup-venv.sh` vs `source setup-venv.sh`)

**Files Changed:**
- `scripts/utils/setup-venv.sh` — full rewrite

---

## Issue #2: `check-prereqs.sh` never actually installed wrk2

**Date:** 2026-04-20  
**Step:** Step 1 — Pre-flight checks  
**Symptom:** In AUTO_INSTALL mode (default), wrk2 was reported as missing but the script only printed compile-from-source instructions. No actual installation was attempted.

**Root Cause:** The wrk2 section only searched 3 hardcoded paths. There was no build/compile logic at all — unlike jq/curl/git which had `install_apt()` calls, wrk2 (which must be compiled from source) had nothing.

**Fix Applied:**
- Added full auto-build pipeline for wrk2 in AUTO_INSTALL mode:
  1. `apt install build-essential gcc make libssl-dev zlib1g-dev luajit libluajit-5.1-dev`
  2. `git clone https://github.com/giltene/wrk2.git /opt/wrk2_src`
  3. `make -C /opt/wrk2_src`
  4. Copy binary to `/opt/wrk2/wrk`
  5. Symlink to `/usr/local/bin/wrk2`
- Added `-R` flag check to distinguish wrk2 from vanilla wrk

**Files Changed:**
- `scripts/utils/check-prereqs.sh` — full rewrite

---

## Issue #3: `check-prereqs.sh` hangs or exits early on cluster checks

**Date:** 2026-04-20  
**Step:** Step 1 — Pre-flight checks  
**Symptom:** `kubectl cluster-info` would hang indefinitely (no timeout), or when running as root, kubectl failed because `/root/.kube/config` doesn't exist (kubeconfig belongs to user `appu`). With `set -e` enabled, the script exited immediately on the first kubectl failure.

**Root Cause:** Two issues compounding:
1. `set -euo pipefail` at the top of the script caused early exit on any check failure
2. No timeout on kubectl commands — they'd wait 30+ seconds per attempt
3. Running as root: kubectl defaults to `$HOME/.kube/config` = `/root/.kube/config`, which doesn't exist when the kubeconfig was set up for a non-root user

**Fix Applied:**
- Removed `set -e` (kept `set -uo pipefail`) — each section handles its own errors
- Wrapped all kubectl calls with `timeout 10s` to prevent hangs
- Reclassified cluster connectivity checks as **informational** (do not increment `ERRORS`)
- Added root-user kubeconfig detection: searches `/home/appu/.kube/config` and other common paths, prints the exact `export KUBECONFIG=...` command needed

**Files Changed:**
- `scripts/utils/check-prereqs.sh` — full rewrite

---

## Issue #4: `deploy-setup.sh` fails with "Chart.yaml file is missing"

**Date:** 2026-04-20  
**Step:** Step 3 — Deploy DSB via Helm  
**Symptom:** `helm upgrade --install` failed with `Error: Chart.yaml file is missing` even though check-prereqs said DSB was cloned.

**Root Cause:** The DSB Helm chart is nested one level deeper than assumed:
- **Assumed path:** `/opt/dsb/socialNetwork/helm-chart/Chart.yaml`
- **Actual path:** `/opt/dsb/socialNetwork/helm-chart/socialnetwork/Chart.yaml`

The script variable `DSB_CHART` pointed to the parent `helm-chart/` directory, which is just a container — the actual chart with `Chart.yaml` lives inside the `socialnetwork/` subdirectory.

**Fix Applied:**
- Changed `DSB_CHART` from `${DSB_REPO}/socialNetwork/helm-chart` to `${DSB_REPO}/socialNetwork/helm-chart/socialnetwork` in both deploy scripts
- Changed the pre-check from `[[ -d "$DSB_CHART" ]]` (directory exists) to `[[ -f "$DSB_CHART/Chart.yaml" ]]` (chart is actually valid)
- Added auto-clone logic: if `Chart.yaml` is missing and the repo is incomplete (no `.git`), auto-removes the broken directory and re-clones

**Files Changed:**
- `scripts/deploy/deploy-setup.sh` — DSB_CHART path + Chart.yaml check + auto-clone
- `scripts/deploy/deploy-dsb.sh` — same DSB_CHART path fix

---

## Issue #5: Helm values used wrong service names and unsupported placement keys

**Date:** 2026-04-20  
**Step:** Step 3 — Deploy DSB via Helm (values files)  
**Symptom:** Even with the correct chart path, Helm would silently ignore placement rules and resource overrides because the YAML keys didn't match what the DSB chart templates expected.

**Root Cause:** Three compounding problems in the Helm values files:
1. **Wrong service names:** Used `nginx-web-server`, `mongodb-social-graph`, `mongodb-post-storage`, etc. — the actual DSB subchart names are `nginx-thrift`, `social-graph-mongodb`, `post-storage-mongodb`, etc.
2. **Wrong placement key:** Used `nodeSelector:` — but DSB's `_baseDeployment.tpl` template only supports `nodeName:` (exact node name, not label-based selection)
3. **Wrong resource nesting:** Used top-level `resources:` — but the template reads `container.resources` (inside the container block), with fallback to `global.resources`

**Fix Applied:**
- Rewrote `helm-values-ambient.yaml`:
  - Corrected all service names to match actual DSB subchart names
  - Moved resource overrides under `container.resources` per the template
  - Set Jaeger sampling to `const` / `param: 1` (100% for baseline)
  - Added all global defaults matching DSB's values.yaml structure
- Rewrote `worker0-affinity.yaml`:
  - Replaced `nodeSelector: { role: worker-0 }` with `nodeName: default-pool-ssp-11b2c93c3e14`
  - Fixed service list to actual names, added missing services (unique-id-service, user-mention-service)
- Rewrote `worker1-affinity.yaml`:
  - Same `nodeSelector` → `nodeName` fix
  - Fixed all service names, added all missing DB services (memcached, per-service MongoDB, per-service Redis)
- Global sed replacement across all 8 shell scripts: `nginx-web-server` → `nginx-thrift`

**Files Changed:**
- `configs/deathstarbench/social-network/base/helm-values-ambient.yaml` — full rewrite
- `configs/deathstarbench/social-network/placement/worker0-affinity.yaml` — full rewrite
- `configs/deathstarbench/social-network/placement/worker1-affinity.yaml` — full rewrite
- `scripts/deploy/deploy-setup.sh` — sed nginx name fix
- `scripts/deploy/verify-deployment.sh` — sed nginx name fix + label selector fix (`app=` → `service=`)
- `scripts/deploy/init-graph.sh` — sed nginx name fix
- `scripts/cleanup/cleanup-deploy-setup.sh` — sed nginx name fix
- `scripts/run/run-experiment.sh` — sed nginx name fix
- `scripts/run/run-saturation-sweep.sh` — sed nginx name fix
- `scripts/metrics/collect-traces.sh` — sed nginx name fix

---

## Issue #6: `init-graph.sh` fails — "NGINX not responding after 10 retries"

**Date:** 2026-04-20  
**Step:** Step 7 (within deploy-setup.sh) — Social graph initialization  
**Symptom:** All 27 DSB pods were Running + Ready, but `curl http://10.96.18.149:8080/` timed out 10 times in a row. The social graph init never started.

**Root Cause:** **ClusterIP is only routable from inside the Kubernetes cluster network.** The user runs the script from WSL on their Windows desktop, connecting to a remote Vultr VKE cluster. A ClusterIP like `10.96.18.149` is a virtual IP that only exists in the cluster's kube-proxy iptables rules — it cannot be reached from an external machine. Every `curl` attempt was silently timing out.

**Fix Applied:**
- Rewrote `init-graph.sh` to use `kubectl port-forward` instead of direct ClusterIP access:
  1. Starts `kubectl port-forward svc/nginx-thrift 18080:8080` in the background
  2. Waits with retry loop until `localhost:18080` is reachable
  3. Runs `init_social_graph.py --ip=127.0.0.1 --port=18080`
  4. Cleans up port-forward on exit via `trap cleanup_pf EXIT INT TERM`
- Added automatic `pip install aiohttp` since DSB's init script requires it (async HTTP client not in our requirements.txt)
- Used port 18080 (not 8080) to avoid conflicts with any local services

**Files Changed:**
- `scripts/deploy/init-graph.sh` — full rewrite

---

## Issue #7: `verify-deployment.sh` used wrong pod label selector

**Date:** 2026-04-20  
**Step:** Step 8 — Verify deployment  
**Symptom:** Would have reported "pod not found" for all victim-tier services because it searched by `app=<name>` label, but DSB chart uses `service=<name>` labels.

**Root Cause:** DSB's `_baseDeployment.tpl` sets labels as `service: {{ .Values.name }}` and `app: {{ .Values.name }}` — but the verify script used wrong service names (`social-graph` instead of `social-graph-service`, `text-filter` instead of `text-service`). 

**Fix Applied:**
- Changed label selector from `-l app=` to `-l service=`
- Fixed service name list to match actual DSB subchart names
- Added missing services to the check list (unique-id-service, user-mention-service)

**Files Changed:**
- `scripts/deploy/verify-deployment.sh` — label selector + service name corrections

---

## Summary: Pattern of Issues

| # | Category | Pattern |
|---|----------|---------|
| 1 | Shell scripting | `set -e` in sourced scripts is dangerous |
| 2–3 | Missing logic | Script reports problems but doesn't fix them |
| 4–5 | Wrong assumptions | Never validated against actual DSB chart structure |
| 6 | Network architecture | ClusterIP ≠ externally routable; need port-forward for remote clusters |
| 7 | Wrong labels | DSB chart conventions differ from what was assumed |

**Key lesson:** Every shell script and YAML file was written against *assumed* DSB chart structure without ever inspecting the actual `Chart.yaml`, `values.yaml`, or `_baseDeployment.tpl` templates. The chart uses `nodeName` (not nodeSelector), `service=` labels (not just `app=`), `container.resources` (not top-level `resources`), and a nested chart path with a `socialnetwork/` subdirectory.
