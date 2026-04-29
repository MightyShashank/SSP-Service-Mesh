# Experiment 12 — Makefile
# Targets: deploy, run, analyze, figures, clean, verify

ROOT := $(shell pwd)
WRK2 ?= $(ROOT)/../wrk2/wrk
DSB_REPO ?= /opt/dsb
N ?= 5                          # number of repetitions (make run-seq N=5)
RUN_ID ?= run_001               # for per-run analysis targets

.PHONY: all deploy verify sweep run run-seq analyze figures clean help

all: help

# ─────────────────────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────────────────────

## Check prerequisites (tools, cluster, DSB repo)
check:
	bash scripts/utils/check-prereqs.sh

## Label cluster nodes
label:
	bash scripts/utils/label-nodes.sh

## Full deploy: labels + namespace + DSB + Jaeger + graph init
deploy:
	DSB_REPO=$(DSB_REPO) bash scripts/deploy/deploy-setup.sh

## Verify deployment state
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

## Run N sequential repetitions (default N=5)
run-seq:
	WRK2=$(WRK2) bash scripts/run/run_sequential_experiments.sh $(N)

# ─────────────────────────────────────────────────────────────────────────────
# ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────

## Parse wrk2 raw outputs → processed CSVs
parse:
	python3 src/parser/wrk2_parser.py \
	  --runs-dir data/raw/ \
	  --output data/processed/csv/

## Compute statistics (median, 95% CI, CV) across repetitions
stats:
	python3 src/analysis/stats.py \
	  --input data/processed/csv/ \
	  --output results/tables/summary.csv

## Full analysis pipeline (parse + stats)
analyze: parse stats

# ─────────────────────────────────────────────────────────────────────────────
# FIGURES
# ─────────────────────────────────────────────────────────────────────────────

## Figure 1: Saturation sweep (P99 vs RPS)
fig-sweep:
	python3 src/plotting/saturation_plots.py \
	  --data data/raw/saturation-sweep/ \
	  --output results/figures/throughput/

## Figure 2: Baseline percentile bars (P50/P99/P99.99 per endpoint)
fig-bars:
	python3 src/plotting/latency_plots.py \
	  --mode latency \
	  --data data/processed/csv/ \
	  --output results/figures/latency-cdf/

## Figure 3: Jaeger flame chart (per-hop latency for compose-post)
fig-jaeger:
	python3 src/plotting/latency_plots.py \
	  --mode jaeger \
	  --data data/raw/$(RUN_ID)/jaeger-traces.json \
	  --output results/figures/traces/

## All paper figures
figures: fig-sweep fig-bars fig-jaeger

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────────────────────────

## Pure cleanup (teardown only — no redeploy)
clean:
	bash scripts/cleanup/cleanup.sh

## Cleanup + redeploy (idempotent — use between manual repetitions)
reset:
	DSB_REPO=$(DSB_REPO) bash scripts/cleanup/cleanup-deploy-setup.sh

# ─────────────────────────────────────────────────────────────────────────────
# HELP
# ─────────────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Experiment 12 — DeathStarBench Baseline Characterization"
	@echo ""
	@echo "Usage: make <target> [WRK2=path] [DSB_REPO=path] [N=5] [RUN_ID=run_001]"
	@echo ""
	@echo "Targets:"
	@echo "  check       Pre-flight checks (tools + cluster)"
	@echo "  deploy      Full deploy (labels + DSB + Jaeger + graph init)"
	@echo "  verify      Verify deployment state"
	@echo "  sweep       Saturation sweep (one-time, before baseline)"
	@echo "  run         Single experiment repetition"
	@echo "  run-seq     N sequential repetitions (default N=5)"
	@echo "  analyze     Parse + compute statistics"
	@echo "  figures     All 3 paper figures"
	@echo "  clean       Teardown DSB and namespace"
	@echo "  reset       Cleanup + redeploy (idempotent)"
	@echo ""
	@echo "Full workflow:"
	@echo "  make check"
	@echo "  make deploy"
	@echo "  make verify"
	@echo "  make sweep"
	@echo "  make run-seq N=5"
	@echo "  make analyze"
	@echo "  make figures"
