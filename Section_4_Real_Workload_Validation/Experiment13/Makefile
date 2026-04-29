# Experiment 13 — Makefile
# Targets: setup, deploy, noisy, run, analyze, figures, clean, help
#
# Prerequisites: .venv must exist (make setup) and cluster must be running.

ROOT    := $(shell pwd)
WRK2    ?= $(ROOT)/../../wrk2/wrk
DSB_REPO ?= /opt/dsb
PYTHON  := $(ROOT)/.venv/bin/python3
CASE    ?= A                         # victim case: A | B | C
MODE    ?= sustained-ramp            # interference mode
NOISY_RPS ?= 200                     # for single-trial testing
REPS    ?= 3                         # repetitions per RPS step
BASELINE := $(ROOT)/../../Experiment12/results/tables/summary.csv

.PHONY: all setup deploy noisy noisy-remove verify \
        smoke run-ramp run-burst run-churn \
        parse parse-traces amplification figures \
        clean help

all: help

# ─────────────────────────────────────────────────────────────────────────────
# STEP 0: SETUP
# ─────────────────────────────────────────────────────────────────────────────

## Create .venv and install Python dependencies
setup:
	bash scripts/utils/setup-venv.sh

## Verify .venv is active and all imports work
check-venv:
	$(PYTHON) -c "import matplotlib, numpy, pandas, scipy; print('[OK] venv imports working')"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: DEPLOY
# ─────────────────────────────────────────────────────────────────────────────

## Deploy DSB (same as Experiment 12 — skip if already running)
deploy:
	DSB_REPO=$(DSB_REPO) bash scripts/deploy/deploy-setup.sh

## Verify deployment state
verify:
	bash scripts/deploy/verify-deployment.sh

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: NOISY NEIGHBOR
# ─────────────────────────────────────────────────────────────────────────────

## Deploy svc-noisy and its backend (both pinned to worker-0)
noisy:
	kubectl apply -f configs/noisy-neighbor/svc-noisy-deploy.yaml
	kubectl wait --for=condition=Ready pod -l app=svc-noisy         -n dsb-exp --timeout=120s
	kubectl wait --for=condition=Ready pod -l app=svc-noisy-backend -n dsb-exp --timeout=120s
	@echo "[OK] svc-noisy deployed. Verify worker-0 placement:"
	kubectl get pods -n dsb-exp -o wide | grep svc-noisy

## Remove svc-noisy (keep DSB running)
noisy-remove:
	kubectl delete -f configs/noisy-neighbor/svc-noisy-deploy.yaml --ignore-not-found
	kubectl get pods -n dsb-exp | grep noisy || echo "[OK] noisy pods removed"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: EXPERIMENT EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

## Quick smoke test: one trial at 200 RPS noisy load, Case A
smoke:
	WRK2=$(WRK2) bash scripts/run/run-experiment.sh \
	  --case A --mode sustained-ramp --noisy-rps 200

## Run full sustained-ramp sweep for CASE (default: A), REPS reps per RPS level
run-ramp:
	WRK2=$(WRK2) bash scripts/run/run-sustained-ramp.sh --case $(CASE) --reps $(REPS)

## Run burst mode trials for CASE (default: A), 3 reps
run-burst:
	for i in 1 2 3; do \
	  WRK2=$(WRK2) bash scripts/run/run-experiment.sh --case $(CASE) --mode burst; \
	  sleep 120; \
	done

## Run connection-churn mode trials for CASE (default: A), 3 reps
run-churn:
	for i in 1 2 3; do \
	  WRK2=$(WRK2) bash scripts/run/run-experiment.sh --case $(CASE) --mode churn; \
	  sleep 120; \
	done

## Run ALL modes for Case A (ramp + burst + churn)
run-all-A:
	$(MAKE) run-ramp  CASE=A REPS=$(REPS)
	$(MAKE) run-burst CASE=A
	$(MAKE) run-churn CASE=A

## Run ALL cases × all modes (full experiment matrix — ~6 hours)
run-all:
	$(MAKE) run-all-A
	$(MAKE) run-ramp CASE=B REPS=$(REPS)
	$(MAKE) run-ramp CASE=C REPS=$(REPS)

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────

## Parse all wrk2 raw outputs → processed CSVs
parse:
	@for case in A B C; do \
	  for mode in sustained-ramp burst churn; do \
	    dir="data/raw/case-$${case}/$${mode}"; \
	    if [ -d "$$dir" ]; then \
	      echo "[PARSE] case-$${case}/$${mode}"; \
	      $(PYTHON) src/parser/wrk2_parser.py \
	        --runs-dir "$$dir" \
	        --output   "data/processed/csv/case-$${case}/$${mode}/"; \
	    fi; \
	  done; \
	done

## Parse Jaeger traces → per-service latency CSVs (for Plot D)
parse-traces:
	@for json in data/raw/case-A/sustained-ramp/trial_*/jaeger-traces.json; do \
	  trial_dir=$$(dirname "$$json"); \
	  trial=$$(basename "$$trial_dir"); \
	  noisy_rps=$$(grep "Noisy RPS:" "$$trial_dir/run-metadata.txt" 2>/dev/null | awk '{print $$NF}' || echo 0); \
	  echo "[TRACES] $$trial  noisy_rps=$$noisy_rps"; \
	  $(PYTHON) src/parser/trace_parser.py \
	    --input     "$$json" \
	    --output    "data/processed/csv/case-A/sustained-ramp/$${trial}/traces/" \
	    --label     noisy \
	    --noisy-rps "$$noisy_rps"; \
	done

## Compute amplification ratios vs Experiment 12 baseline
amplification:
	$(PYTHON) src/analysis/amplification.py \
	  --baseline $(BASELINE) \
	  --data     data/processed/csv/ \
	  --output   results/tables/amplification.csv

## Full analysis pipeline: parse + parse-traces + amplification
analyze: parse parse-traces amplification

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5: FIGURES
# ─────────────────────────────────────────────────────────────────────────────

## Generate all 7 paper figures (placeholders for plots with no data yet)
figures:
	$(PYTHON) src/plotting/exp13_plots.py \
	  --data        data/processed/csv/ \
	  --traces-dir  data/processed/csv/ \
	  --ztunnel-dir data/raw/ \
	  --baseline    $(BASELINE) \
	  --output      results/figures/

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────────────────────────

## Remove svc-noisy pods (keep DSB running)
clean-noisy: noisy-remove

## Full cleanup (DSB + namespace teardown)
clean:
	bash scripts/cleanup/cleanup.sh

## Cleanup + redeploy (idempotent reset between runs)
reset:
	DSB_REPO=$(DSB_REPO) bash scripts/cleanup/cleanup-deploy-setup.sh

# ─────────────────────────────────────────────────────────────────────────────
# HELP
# ─────────────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Experiment 13 — Noisy Neighbor Injection into DeathStarBench"
	@echo ""
	@echo "Usage: make <target> [CASE=A|B|C] [MODE=sustained-ramp|burst|churn] [REPS=3]"
	@echo ""
	@echo "── Setup ─────────────────────────────────────────────────────────"
	@echo "  setup          Create .venv and install Python dependencies"
	@echo "  check-venv     Verify .venv imports work"
	@echo ""
	@echo "── Deploy ────────────────────────────────────────────────────────"
	@echo "  deploy         Deploy DSB (skip if already running from Exp12)"
	@echo "  verify         Verify deployment state"
	@echo "  noisy          Deploy svc-noisy + backend on worker-0"
	@echo "  noisy-remove   Remove svc-noisy (keep DSB running)"
	@echo ""
	@echo "── Experiment ────────────────────────────────────────────────────"
	@echo "  smoke          Quick 1-trial test (Case A, 200 RPS noisy)"
	@echo "  run-ramp       Sustained-ramp sweep for CASE (default A)"
	@echo "  run-burst      Burst mode 3 reps for CASE"
	@echo "  run-churn      Churn mode 3 reps for CASE"
	@echo "  run-all-A      All modes for Case A"
	@echo "  run-all        Full experiment matrix (all cases + modes, ~6h)"
	@echo ""
	@echo "── Analysis ──────────────────────────────────────────────────────"
	@echo "  parse          Parse wrk2 outputs → CSVs"
	@echo "  parse-traces   Parse Jaeger traces → per-service CSV"
	@echo "  amplification  Compute amplification ratios vs Exp12 baseline"
	@echo "  analyze        parse + parse-traces + amplification"
	@echo ""
	@echo "── Figures ───────────────────────────────────────────────────────"
	@echo "  figures        Generate all 7 paper figures"
	@echo ""
	@echo "── Cleanup ───────────────────────────────────────────────────────"
	@echo "  clean-noisy    Remove svc-noisy pods"
	@echo "  clean          Full teardown"
	@echo "  reset          Cleanup + redeploy (idempotent)"
	@echo ""
	@echo "Recommended workflow:"
	@echo "  make setup"
	@echo "  make deploy && make verify"
	@echo "  make noisy"
	@echo "  make smoke"
	@echo "  make run-all-A"
	@echo "  make analyze"
	@echo "  make figures"
	@echo ""
