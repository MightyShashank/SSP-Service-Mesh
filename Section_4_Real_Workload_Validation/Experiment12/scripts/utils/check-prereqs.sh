#!/bin/bash
# Pre-flight validation for Experiment 12.
# Checks that all tools, the venv, Python packages, cluster state, and
# DSB repo are ready.
#
# AUTO-INSTALL behaviour (default mode):
#   - System tools (jq, curl, git, shellcheck): apt-get install
#   - helm: official get-helm-3 script
#   - wrk2: clones https://github.com/giltene/wrk2 → /opt/wrk2, runs make
#   - DSB repo: git clone → /opt/dsb
#
# wrk2 and DSB clone can take several minutes on first run.
# kubectl / Istio checks are INFORMATIONAL — they never fail the script
# because the cluster may not be reachable from every machine.
#
# Usage:
#   bash check-prereqs.sh              # check + auto-install
#   bash check-prereqs.sh --check-only # report only, install nothing

# ── This script is run with "bash", not sourced, so set -e is safe here ──────
set -uo pipefail
# NOTE: -e is intentionally omitted at the top level so the script never exits
# early on a single check failure. Each section handles its own errors.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAMESPACE="dsb-exp"
DSB_REPO="${DSB_REPO:-/opt/dsb}"
WRK2_INSTALL_DIR="${WRK2_INSTALL_DIR:-/opt/wrk2}"
VENV_DIR="$ROOT_DIR/.venv"

# Parse flags
AUTO_INSTALL=true
if [[ "${1:-}" == "--check-only" ]]; then
  AUTO_INSTALL=false
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
log()   { echo -e "\n[INFO] $1"; }
warn()  { echo -e "\n[WARN] $1"; }
tick()  { echo -e "\033[1;32m  ✔ $1\033[0m"; }
cross() { echo -e "\033[1;31m  ✘ $1\033[0m"; }
info()  { echo -e "\033[1;34m  ℹ $1\033[0m"; }

ERRORS=0
INSTALLED=0

# check CMD DESC — runs CMD silently; returns 0/1; never exits the script
_check_cmd() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    tick "$desc"
    return 0
  else
    cross "$desc"
    ERRORS=$((ERRORS + 1))
    return 1
  fi
}

install_apt() {
  local pkg="$1"
  local name="${2:-$1}"
  if $AUTO_INSTALL; then
    echo -e "    → Installing $name via apt..."
    sudo apt-get update -qq > /dev/null 2>&1 || true
    if sudo apt-get install -y -qq "$pkg" > /dev/null 2>&1; then
      tick "$name installed"
      INSTALLED=$((INSTALLED + 1))
      ERRORS=$((ERRORS > 0 ? ERRORS - 1 : 0))
    else
      warn "Failed to install $name — run manually: sudo apt install $pkg"
    fi
  else
    echo "    → Run: sudo apt install $pkg"
  fi
}

echo ""
echo "============================================"
echo "  Experiment 12 — Pre-Flight Checks"
if $AUTO_INSTALL; then
  echo "  Mode: CHECK + AUTO-INSTALL"
else
  echo "  Mode: CHECK ONLY"
fi
echo "============================================"

# ══════════════════════════════════════════════════════════════════════════════
# 1. PYTHON VENV (must be active)
# ══════════════════════════════════════════════════════════════════════════════
log "Checking Python virtual environment..."

if [[ -n "${VIRTUAL_ENV:-}" ]]; then
  tick "venv is ACTIVE → $VIRTUAL_ENV"
  tick "Python: $(python3 --version 2>&1) at $(which python3)"
elif [[ -d "$VENV_DIR" && -f "$VENV_DIR/bin/activate" ]]; then
  cross "venv exists at .venv/ but is NOT activated"
  echo ""
  echo "    ┌──────────────────────────────────────────────┐"
  echo "    │  Run this first (note the 'source'):         │"
  echo "    │                                              │"
  echo "    │    source scripts/utils/setup-venv.sh        │"
  echo "    │                                              │"
  echo "    │  Then re-run:                                │"
  echo "    │    bash scripts/utils/check-prereqs.sh       │"
  echo "    └──────────────────────────────────────────────┘"
  echo ""
  ERRORS=$((ERRORS + 1))
else
  cross "venv not found at .venv/"
  echo ""
  echo "    ┌──────────────────────────────────────────────┐"
  echo "    │  Create + activate the venv first:           │"
  echo "    │                                              │"
  echo "    │    source scripts/utils/setup-venv.sh        │"
  echo "    │                                              │"
  echo "    │  Then re-run:                                │"
  echo "    │    bash scripts/utils/check-prereqs.sh       │"
  echo "    └──────────────────────────────────────────────┘"
  echo ""
  ERRORS=$((ERRORS + 1))
fi

# ══════════════════════════════════════════════════════════════════════════════
# 2. PYTHON PACKAGES
# ══════════════════════════════════════════════════════════════════════════════
log "Checking Python packages..."

for PKG in pandas matplotlib scipy numpy; do
  if python3 -c "import $PKG" > /dev/null 2>&1; then
    VERSION=$(python3 -c "import $PKG; print($PKG.__version__)" 2>/dev/null || echo "?")
    tick "$PKG ($VERSION)"
  else
    cross "$PKG not importable"
    ERRORS=$((ERRORS + 1))
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
      echo "    → Run: pip install $PKG"
    else
      echo "    → Activate venv first, then: pip install -r requirements.txt"
    fi
  fi
done

# ══════════════════════════════════════════════════════════════════════════════
# 3. SYSTEM TOOLS
# ══════════════════════════════════════════════════════════════════════════════
log "Checking required system tools..."

# kubectl binary (not connectivity — that's checked separately)
if _check_cmd "kubectl (binary)" kubectl version --client; then
  : # ok
else
  echo "    → Install: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
fi

# helm
if ! _check_cmd "helm (v3.x)" helm version; then
  if $AUTO_INSTALL; then
    echo "    → Installing helm via get-helm-3 script..."
    if curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash > /dev/null 2>&1; then
      tick "helm installed"
      INSTALLED=$((INSTALLED + 1))
      ERRORS=$((ERRORS > 0 ? ERRORS - 1 : 0))
    else
      warn "helm install failed — see https://helm.sh/docs/intro/install/"
    fi
  else
    echo "    → Run: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
  fi
fi

# simple apt-installable tools
for TOOL in jq curl git; do
  if ! _check_cmd "$TOOL" "$TOOL" --version; then
    install_apt "$TOOL" "$TOOL"
  fi
done

# shellcheck (optional — failure never counted as hard error)
if ! command -v shellcheck > /dev/null 2>&1; then
  info "shellcheck not found (optional lint tool)"
  if $AUTO_INSTALL; then
    sudo apt-get install -y -qq shellcheck > /dev/null 2>&1 && \
      tick "shellcheck installed" || true
  fi
else
  tick "shellcheck (optional)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 4. WRK2
# Hunt for the binary in well-known locations. If missing and AUTO_INSTALL
# is on, clone the repo and compile it at $WRK2_INSTALL_DIR.
# The compiled binary lands at: $WRK2_INSTALL_DIR/wrk
# A symlink is also placed at: /usr/local/bin/wrk2
# ══════════════════════════════════════════════════════════════════════════════
log "Checking wrk2..."

WRK2_PATH=""
# Search order: project-local → install dir → system PATH
for candidate in \
    "$ROOT_DIR/../wrk2/wrk" \
    "$WRK2_INSTALL_DIR/wrk" \
    "$(command -v wrk2 2>/dev/null || true)" \
    "$(command -v wrk  2>/dev/null || true)"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    # Confirm it's wrk2, not vanilla wrk (wrk2 has -R flag)
    if "$candidate" --help 2>&1 | grep -q -- '-R'; then
      WRK2_PATH="$candidate"
      break
    fi
  fi
done

if [[ -n "$WRK2_PATH" ]]; then
  tick "wrk2 found → $WRK2_PATH"
else
  cross "wrk2 not found"
  if $AUTO_INSTALL; then
    echo "    → Building wrk2 from source at $WRK2_INSTALL_DIR ..."
    echo "      (This takes 1–3 minutes. Install deps + compile.)"

    # Install build dependencies
    echo "    → Installing build dependencies (gcc, make, libssl-dev, libz-dev, luajit)..."
    sudo apt-get update -qq > /dev/null 2>&1 || true
    if ! sudo apt-get install -y -qq \
        build-essential gcc make git libssl-dev zlib1g-dev \
        luajit libluajit-5.1-dev > /dev/null 2>&1; then
      warn "Could not install all build deps — wrk2 compile may fail"
    fi

    # Clone
    WRK2_SRC="${WRK2_INSTALL_DIR}_src"
    if [[ ! -d "$WRK2_SRC/.git" ]]; then
      echo "    → Cloning wrk2..."
      sudo mkdir -p "$WRK2_SRC"
      if ! sudo git clone https://github.com/giltene/wrk2.git "$WRK2_SRC" > /dev/null 2>&1; then
        warn "git clone failed — compile wrk2 manually:"
        echo "      git clone https://github.com/giltene/wrk2.git /opt/wrk2_src"
        echo "      cd /opt/wrk2_src && make"
        ERRORS=$((ERRORS + 1))
      fi
    else
      echo "    → Source already present at $WRK2_SRC, pulling latest..."
      sudo git -C "$WRK2_SRC" pull --quiet > /dev/null 2>&1 || true
    fi

    # Compile
    if [[ -d "$WRK2_SRC" ]]; then
      echo "    → Compiling wrk2 (make)..."
      if sudo make -C "$WRK2_SRC" > /dev/null 2>&1; then
        sudo mkdir -p "$WRK2_INSTALL_DIR"
        sudo cp "$WRK2_SRC/wrk" "$WRK2_INSTALL_DIR/wrk"
        sudo chmod +x "$WRK2_INSTALL_DIR/wrk"
        # Symlink so it's on PATH as "wrk2"
        sudo ln -sf "$WRK2_INSTALL_DIR/wrk" /usr/local/bin/wrk2
        tick "wrk2 compiled → $WRK2_INSTALL_DIR/wrk  (symlinked: /usr/local/bin/wrk2)"
        INSTALLED=$((INSTALLED + 1))
        ERRORS=$((ERRORS > 0 ? ERRORS - 1 : 0))
        WRK2_PATH="$WRK2_INSTALL_DIR/wrk"
      else
        warn "make failed — try manually:"
        echo "      sudo apt install build-essential libssl-dev zlib1g-dev luajit libluajit-5.1-dev"
        echo "      git clone https://github.com/giltene/wrk2.git /opt/wrk2_src && cd /opt/wrk2_src && make"
        ERRORS=$((ERRORS + 1))
      fi
    fi
  else
    echo "    → Compile from source (takes ~2 min):"
    echo "      sudo apt install build-essential libssl-dev zlib1g-dev luajit libluajit-5.1-dev"
    echo "      git clone https://github.com/giltene/wrk2.git /opt/wrk2_src"
    echo "      cd /opt/wrk2_src && make"
    echo "      sudo cp /opt/wrk2_src/wrk /opt/wrk2/wrk"
    echo "      sudo ln -sf /opt/wrk2/wrk /usr/local/bin/wrk2"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# 5. CLUSTER STATE
# These checks are INFORMATIONAL. A missing kubeconfig or unreachable cluster
# does not block local file creation. Failures are reported but do NOT
# increment ERRORS — the deploy scripts will catch connectivity problems.
# ══════════════════════════════════════════════════════════════════════════════
log "Checking cluster connectivity (informational — does not block setup)..."

# Diagnose kubeconfig location
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
if [[ -f "$KUBECONFIG_PATH" ]]; then
  info "kubeconfig → $KUBECONFIG_PATH"
else
  info "No kubeconfig found at $KUBECONFIG_PATH"
  # If running as root, check if the regular user's config exists
  if [[ "$EUID" -eq 0 ]]; then
    SUDO_USER_HOME=$(getent passwd "${SUDO_USER:-}" 2>/dev/null | cut -d: -f6 || echo "")
    if [[ -n "$SUDO_USER_HOME" && -f "$SUDO_USER_HOME/.kube/config" ]]; then
      info "Found kubeconfig for user '${SUDO_USER}' at $SUDO_USER_HOME/.kube/config"
      echo "    → To use it as root, run:"
      echo "      export KUBECONFIG=$SUDO_USER_HOME/.kube/config"
      echo "    → Or copy it:"
      echo "      mkdir -p /root/.kube && cp $SUDO_USER_HOME/.kube/config /root/.kube/config"
    fi
    # Try common non-root user homes
    for UNAME in appu ubuntu user; do
      USR_HOME="/home/$UNAME"
      if [[ -f "$USR_HOME/.kube/config" ]]; then
        info "Found kubeconfig at $USR_HOME/.kube/config (for user '$UNAME')"
        echo "    → To use as root: export KUBECONFIG=$USR_HOME/.kube/config"
        break
      fi
    done
  fi
fi

# Run connectivity checks with a hard timeout so the script never hangs
if command -v timeout > /dev/null 2>&1; then
  _kube() { timeout 10s kubectl "$@" 2>/dev/null; }
else
  _kube() { kubectl "$@" 2>/dev/null; }
fi

if _kube cluster-info > /dev/null 2>&1; then
  tick "kubectl cluster-info (reachable)"

  # Node count
  READY_NODES=$(_kube get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)
  if [[ "$READY_NODES" -ge 3 ]]; then
    tick "≥ 3 nodes Ready ($READY_NODES found)"
  else
    cross "Only $READY_NODES node(s) Ready (need ≥ 3)"
    info "Not counted as hard error — cluster checks are informational"
  fi

  # Istio
  log "Checking Istio Ambient..."
  if _kube get daemonset ztunnel -n istio-system > /dev/null 2>&1; then
    tick "ztunnel DaemonSet present"
  else
    cross "ztunnel DaemonSet not found in istio-system"
    echo "    → Run: bash scripts/deploy/deploy-istio-ambient.sh"
    info "Not counted as hard error — install Istio before running deploy-setup.sh"
  fi
else
  cross "kubectl cluster-info — cannot reach cluster"
  echo ""
  echo "    This is expected if you are running pre-flight checks on a"
  echo "    workstation before SSHing to the cluster. The deploy scripts"
  echo "    will fail if kubectl is not connected when you actually deploy."
  echo ""
  if [[ "$EUID" -eq 0 ]]; then
    echo "    You are running as root. If your kubeconfig belongs to another"
    echo "    user, export it first:"
    echo "      export KUBECONFIG=/home/<youruser>/.kube/config"
  fi
  info "Cluster reachability is INFORMATIONAL — not counted as a hard error"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 6. DSB REPO
# ══════════════════════════════════════════════════════════════════════════════
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
    echo "    → Cloning DeathStarBench to $DSB_REPO (this takes ~1 min)..."
    sudo mkdir -p "$(dirname "$DSB_REPO")" 2>/dev/null || true
    if sudo git clone https://github.com/delimitrou/DeathStarBench.git "$DSB_REPO" 2>/dev/null; then
      tick "DSB repo cloned → $DSB_REPO"
      INSTALLED=$((INSTALLED + 1))
      ERRORS=$((ERRORS > 0 ? ERRORS - 1 : 0))
    else
      warn "Clone failed — run manually:"
      echo "      sudo git clone https://github.com/delimitrou/DeathStarBench.git $DSB_REPO"
      ERRORS=$((ERRORS + 1))
    fi
  else
    echo "    → Run: sudo git clone https://github.com/delimitrou/DeathStarBench.git $DSB_REPO"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
if [[ $ERRORS -lt 0 ]]; then ERRORS=0; fi

echo ""
echo "============================================"
if [[ "$ERRORS" -eq 0 ]]; then
  echo -e "  \033[1;32m✔ All checks passed — ready to deploy\033[0m"
  if [[ $INSTALLED -gt 0 ]]; then
    echo "    ($INSTALLED item(s) were auto-installed)"
  fi
  echo ""
  echo "  Next: bash scripts/deploy/deploy-setup.sh"
  echo "    or: make deploy"
else
  echo -e "  \033[1;31m✘ $ERRORS hard check(s) failed — see above\033[0m"
  echo ""
  echo "  Cluster connectivity failures are INFORMATIONAL and not counted."
  echo "  Fix the items above (wrk2, DSB repo, Python packages) before deploying."
fi
echo "============================================"
echo ""

exit "$ERRORS"
