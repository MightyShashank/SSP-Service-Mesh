#!/bin/bash
# Pre-flight validation for Experiment 11 (plain Kubernetes, NO Istio).
# Checks: venv, Python packages, system tools, wrk2, cluster state, DSB repo.
# NOTE: No Istio / ztunnel checks — this experiment runs on plain K8s.
#
# Usage:
#   bash check-prereqs.sh              # check + auto-install
#   bash check-prereqs.sh --check-only # report only, install nothing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAMESPACE="dsb-exp11"
DSB_REPO="${DSB_REPO:-/opt/dsb}"
WRK2_INSTALL_DIR="${WRK2_INSTALL_DIR:-/opt/wrk2}"
VENV_DIR="$ROOT_DIR/.venv"

AUTO_INSTALL=true
if [[ "${1:-}" == "--check-only" ]]; then
  AUTO_INSTALL=false
fi

log()   { echo -e "\n[INFO] $1"; }
warn()  { echo -e "\n[WARN] $1"; }
tick()  { echo -e "\033[1;32m  ✔ $1\033[0m"; }
cross() { echo -e "\033[1;31m  ✘ $1\033[0m"; }
info()  { echo -e "\033[1;34m  ℹ $1\033[0m"; }

ERRORS=0
INSTALLED=0

_check_cmd() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    tick "$desc"; return 0
  else
    cross "$desc"; ERRORS=$((ERRORS + 1)); return 1
  fi
}

install_apt() {
  local pkg="$1"; local name="${2:-$1}"
  if $AUTO_INSTALL; then
    echo -e "    → Installing $name via apt..."
    sudo apt-get update -qq > /dev/null 2>&1 || true
    if sudo apt-get install -y -qq "$pkg" > /dev/null 2>&1; then
      tick "$name installed"
      INSTALLED=$((INSTALLED + 1))
      ERRORS=$((ERRORS > 0 ? ERRORS - 1 : 0))
    else
      warn "Failed to install $name"
    fi
  else
    echo "    → Run: sudo apt install $pkg"
  fi
}

echo ""
echo "============================================"
echo "  Experiment 11 — Pre-Flight Checks"
echo "  (plain Kubernetes — NO Istio)"
if $AUTO_INSTALL; then echo "  Mode: CHECK + AUTO-INSTALL"
else echo "  Mode: CHECK ONLY"; fi
echo "============================================"

# ── 1. PYTHON VENV ───────────────────────────────────────────────────────────
log "Checking Python virtual environment..."
if [[ -n "${VIRTUAL_ENV:-}" ]]; then
  tick "venv is ACTIVE → $VIRTUAL_ENV"
  tick "Python: $(python3 --version 2>&1) at $(which python3)"
elif [[ -d "$VENV_DIR" && -f "$VENV_DIR/bin/activate" ]]; then
  cross "venv exists at .venv/ but is NOT activated"
  echo ""; echo "    ┌──────────────────────────────────────────────┐"
  echo "    │  Run this first (note the 'source'):         │"
  echo "    │    source scripts/utils/setup-venv.sh        │"
  echo "    │  Then re-run:                                │"
  echo "    │    bash scripts/utils/check-prereqs.sh       │"
  echo "    └──────────────────────────────────────────────┘"; echo ""
  ERRORS=$((ERRORS + 1))
else
  cross "venv not found at .venv/"
  echo ""; echo "    ┌──────────────────────────────────────────────┐"
  echo "    │  Create + activate the venv first:           │"
  echo "    │    source scripts/utils/setup-venv.sh        │"
  echo "    └──────────────────────────────────────────────┘"; echo ""
  ERRORS=$((ERRORS + 1))
fi

# ── 2. PYTHON PACKAGES ───────────────────────────────────────────────────────
log "Checking Python packages..."
for PKG in pandas matplotlib scipy numpy; do
  if python3 -c "import $PKG" > /dev/null 2>&1; then
    VERSION=$(python3 -c "import $PKG; print($PKG.__version__)" 2>/dev/null || echo "?")
    tick "$PKG ($VERSION)"
  else
    cross "$PKG not importable"
    ERRORS=$((ERRORS + 1))
  fi
done

# ── 3. SYSTEM TOOLS ──────────────────────────────────────────────────────────
log "Checking required system tools..."
if _check_cmd "kubectl (binary)" kubectl version --client; then : ; else
  echo "    → Install: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
fi
if ! _check_cmd "helm (v3.x)" helm version; then
  if $AUTO_INSTALL; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash > /dev/null 2>&1 \
      && { tick "helm installed"; INSTALLED=$((INSTALLED + 1)); ERRORS=$((ERRORS > 0 ? ERRORS - 1 : 0)); } \
      || warn "helm install failed — see https://helm.sh/docs/intro/install/"
  fi
fi
for TOOL in jq curl git; do
  if ! _check_cmd "$TOOL" "$TOOL" --version; then install_apt "$TOOL" "$TOOL"; fi
done

# ── 4. WRK2 ──────────────────────────────────────────────────────────────────
log "Checking wrk2..."
WRK2_PATH=""
for candidate in \
    "$ROOT_DIR/../wrk2/wrk" \
    "$WRK2_INSTALL_DIR/wrk" \
    "$(command -v wrk2 2>/dev/null || true)" \
    "$(command -v wrk  2>/dev/null || true)"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    if "$candidate" --help 2>&1 | grep -q -- '-R'; then
      WRK2_PATH="$candidate"; break
    fi
  fi
done
if [[ -n "$WRK2_PATH" ]]; then
  tick "wrk2 found → $WRK2_PATH"
else
  cross "wrk2 not found"
  ERRORS=$((ERRORS + 1))
  if $AUTO_INSTALL; then
    echo "    → Building wrk2 from source at $WRK2_INSTALL_DIR ..."
    sudo apt-get update -qq > /dev/null 2>&1 || true
    sudo apt-get install -y -qq build-essential gcc make git libssl-dev zlib1g-dev luajit libluajit-5.1-dev > /dev/null 2>&1 || true
    WRK2_SRC="${WRK2_INSTALL_DIR}_src"
    if [[ ! -d "$WRK2_SRC/.git" ]]; then
      sudo mkdir -p "$WRK2_SRC"
      sudo git clone https://github.com/giltene/wrk2.git "$WRK2_SRC" > /dev/null 2>&1 || true
    fi
    if [[ -d "$WRK2_SRC" ]] && sudo make -C "$WRK2_SRC" > /dev/null 2>&1; then
      sudo mkdir -p "$WRK2_INSTALL_DIR"
      sudo cp "$WRK2_SRC/wrk" "$WRK2_INSTALL_DIR/wrk"
      sudo chmod +x "$WRK2_INSTALL_DIR/wrk"
      sudo ln -sf "$WRK2_INSTALL_DIR/wrk" /usr/local/bin/wrk2
      tick "wrk2 compiled → $WRK2_INSTALL_DIR/wrk"
      INSTALLED=$((INSTALLED + 1)); ERRORS=$((ERRORS > 0 ? ERRORS - 1 : 0))
    else
      warn "make failed — build wrk2 manually"
    fi
  fi
fi

# ── 5. CLUSTER STATE (informational) ─────────────────────────────────────────
log "Checking cluster connectivity (informational — does not block setup)..."
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
if [[ -f "$KUBECONFIG_PATH" ]]; then
  info "kubeconfig → $KUBECONFIG_PATH"
else
  info "No kubeconfig found at $KUBECONFIG_PATH"
fi

if command -v timeout > /dev/null 2>&1; then
  _kube() { timeout 10s kubectl "$@" 2>/dev/null; }
else
  _kube() { kubectl "$@" 2>/dev/null; }
fi

if _kube cluster-info > /dev/null 2>&1; then
  tick "kubectl cluster-info (reachable)"

  READY_NODES=$(_kube get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)
  if [[ "$READY_NODES" -ge 3 ]]; then
    tick "≥ 3 nodes Ready ($READY_NODES found)"
  else
    cross "Only $READY_NODES node(s) Ready (need ≥ 3)"
    info "Not counted as hard error — informational"
  fi

  # Confirm NO Istio running (informational)
  log "Checking Istio status (should be absent for Experiment 11)..."
  if _kube get daemonset ztunnel -n istio-system > /dev/null 2>&1; then
    info "ztunnel DaemonSet found — Istio IS running on this cluster"
    info "Experiment 11 uses namespace dsb-exp11 with NO Istio label — traffic goes plain K8s"
    info "Make sure dsb-exp11 namespace has NO istio.io/dataplane-mode label"
  else
    tick "No ztunnel DaemonSet (correct for plain K8s experiment)"
  fi
else
  cross "kubectl cluster-info — cannot reach cluster"
  info "Cluster reachability is INFORMATIONAL — not counted as a hard error"
fi

# ── 6. DSB REPO ──────────────────────────────────────────────────────────────
log "Checking DeathStarBench repository..."
if [[ -d "$DSB_REPO/socialNetwork" ]]; then
  tick "DSB repo present → $DSB_REPO"
  if [[ -f "$DSB_REPO/socialNetwork/scripts/init_social_graph.py" ]]; then
    tick "DSB init script present"
  else
    cross "init_social_graph.py missing (repo may be incomplete)"
    ERRORS=$((ERRORS + 1))
  fi
else
  cross "DSB repo not found at $DSB_REPO"
  if $AUTO_INSTALL; then
    sudo mkdir -p "$(dirname "$DSB_REPO")" 2>/dev/null || true
    if sudo git clone https://github.com/delimitrou/DeathStarBench.git "$DSB_REPO" 2>/dev/null; then
      tick "DSB repo cloned → $DSB_REPO"
      INSTALLED=$((INSTALLED + 1)); ERRORS=$((ERRORS > 0 ? ERRORS - 1 : 0))
    else
      warn "Clone failed — run: sudo git clone https://github.com/delimitrou/DeathStarBench.git $DSB_REPO"
      ERRORS=$((ERRORS + 1))
    fi
  fi
fi

# ── SUMMARY ──────────────────────────────────────────────────────────────────
if [[ $ERRORS -lt 0 ]]; then ERRORS=0; fi

echo ""
echo "============================================"
if [[ "$ERRORS" -eq 0 ]]; then
  echo -e "  \033[1;32m✔ All checks passed — ready to deploy\033[0m"
  [[ $INSTALLED -gt 0 ]] && echo "    ($INSTALLED item(s) were auto-installed)"
  echo ""; echo "  Next: bash scripts/deploy/deploy-setup.sh"
  echo "    or: make deploy"
else
  echo -e "  \033[1;31m✘ $ERRORS hard check(s) failed — see above\033[0m"
  echo ""; echo "  Fix the items above before deploying."
fi
echo "============================================"; echo ""

exit "$ERRORS"
