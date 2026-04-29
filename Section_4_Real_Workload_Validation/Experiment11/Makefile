# Experiment 11 — Makefile
# Plain Kubernetes baseline (NO Istio / ztunnel)
# Measures identical metrics to Experiment 12 for a direct mesh-vs-no-mesh comparison.

ROOT    := $(shell pwd)
WRK2    ?= $(ROOT)/../../wrk2/wrk
DSB_REPO ?= /opt/dsb
PYTHON  := $(ROOT)/.venv/bin/python3
N       ?= 5          # number of repetitions (make run-seq N=5)
RUN_ID  ?= run_001    # for per-run analysis targets

.PHONY: all setup check check-venv deploy verify sweep run run-seq \
        parse stats analyze figures figure-bars figure-cdf figure-sweep \
        clean reset help

all: help

# ─────────────────────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────────────────────

## Create .venv and install Python dependencies
setup:
	bash scripts/utils/setup-venv.sh

## Verify .venv is active and all imports work
check-venv:
	$(PYTHON) -c "import matplotlib, numpy, pandas, scipy; print('[OK] venv imports working')"

## Check prerequisites (tools, cluster, DSB repo) — no Istio check
check:
	bash scripts/utils/check-prereqs.sh

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOY (plain Kubernetes — NO Istio)
# ─────────────────────────────────────────────────────────────────────────────

## Label cluster nodes
label:
	bash scripts/utils/label-nodes.sh

## Full deploy: labels + namespace (no Istio) + DSB + Jaeger + graph init
deploy:
	DSB_REPO=$(DSB_REPO) bash scripts/deploy/deploy-setup.sh

## Verify deployment state (no ztunnel checks)
verify:
	bash scripts/deploy/verify-deployment.sh

# ─────────────────────────────────────────────────────────────────────────────
# EXPERIMENT EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

## Run saturation sweep (one-time, before 5-rep baseline)
sweep:
	WRK2=$(WRK2) bash scripts/run/run-saturation-sweep.sh

## Run a single experiment repetition
run:
	WRK2=$(WRK2) bash scripts/run/run-experiment.sh

## Run N sequential repetitions with fresh deploy between each (default N=5)
run-seq:
	WRK2=$(WRK2) bash scripts/run/run_sequential_experiments.sh $(N)

# ─────────────────────────────────────────────────────────────────────────────
# ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────

## Parse all wrk2 raw outputs → processed CSVs
parse:
	$(PYTHON) src/parser/wrk2_parser.py \
	  --runs-dir data/raw/ \
	  --output   data/processed/csv/

## Compute statistics (median, 95% CI, CV) across repetitions
stats:
	$(PYTHON) src/analysis/stats.py \
	  --input  data/processed/csv/ \
	  --output results/tables/summary.csv

## Full analysis pipeline (parse + stats)
analyze: parse stats

# ─────────────────────────────────────────────────────────────────────────────
# FIGURES
# ─────────────────────────────────────────────────────────────────────────────

## Figure A: Baseline percentile bars (P50/P99/P99.99 per endpoint)
figure-bars:
	$(PYTHON) src/plotting/latency_plots.py \
	  --mode latency \
	  --data data/processed/csv/ \
	  --output results/figures/latency-cdf/

## Figure B: Throughput vs offered load (dual-panel: achieved RPS + P99)
figure-throughput:
	$(PYTHON) src/plotting/throughput_plots.py \
	  --data data/raw/saturation-sweep/ \
	  --output results/figures/throughput/

## Figure C: Saturation sweep (P99 vs RPS)
figure-sweep:
	$(PYTHON) src/plotting/saturation_plots.py \
	  --data data/raw/saturation-sweep/ \
	  --output results/figures/throughput/

## Figure D: Endpoint tail CCDF (log Y-axis)
figure-cdf:
	$(PYTHON) src/plotting/cdf_plots.py \
	  --runs-dir data/raw/ \
	  --output results/figures/latency-cdf/

## All paper figures
figures: figure-bars figure-throughput figure-sweep figure-cdf

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────────────────────────

## Full teardown (DSB + namespace)
clean:
	bash scripts/cleanup/cleanup.sh

## Cleanup + redeploy (idempotent — use between repetitions)
reset:
	DSB_REPO=$(DSB_REPO) bash scripts/cleanup/cleanup-deploy-setup.sh

# ─────────────────────────────────────────────────────────────────────────────
# HELP
# ─────────────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Experiment 11 — DeathStarBench Baseline (plain Kubernetes, NO Istio)"
	@echo ""
	@echo "Usage: make <target> [WRK2=path] [DSB_REPO=path] [N=5]"
	@echo ""
	@echo "── Setup ──────────────────────────────────────────────────────────"
	@echo "  setup       Create .venv and install Python dependencies"
	@echo "  check-venv  Verify .venv imports work"
	@echo "  check       Pre-flight checks (tools + cluster)"
	@echo ""
	@echo "── Deploy ─────────────────────────────────────────────────────────"
	@echo "  label       Label cluster nodes"
	@echo "  deploy      Full deploy (namespace + DSB + Jaeger + graph init)"
	@echo "  verify      Verify deployment state (no ztunnel checks)"
	@echo ""
	@echo "── Experiment ─────────────────────────────────────────────────────"
	@echo "  sweep       Saturation sweep (one-time, before baseline)"
	@echo "  run         Single experiment repetition"
	@echo "  run-seq     N sequential repetitions (default N=5)"
	@echo ""
	@echo "── Analysis ───────────────────────────────────────────────────────"
	@echo "  parse       Parse wrk2 outputs → CSVs"
	@echo "  stats       Compute statistics (median, 95% CI, CV)"
	@echo "  analyze     parse + stats"
	@echo ""
	@echo "── Figures ────────────────────────────────────────────────────────"
	@echo "  figures     All paper figures"
	@echo ""
	@echo "── Cleanup ────────────────────────────────────────────────────────"
	@echo "  clean       Full teardown (namespace dsb-exp11)"
	@echo "  reset       Cleanup + redeploy (idempotent)"
	@echo ""
	@echo "Recommended full workflow:"
	@echo "  make setup"
	@echo "  make deploy && make verify"
	@echo "  make sweep"
	@echo "  make run-seq N=5"
	@echo "  make analyze"
	@echo "  make figures"
	@echo ""
