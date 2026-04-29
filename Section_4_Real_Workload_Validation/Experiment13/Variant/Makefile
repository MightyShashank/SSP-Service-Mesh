# Experiment 13 — VARIANT Makefile
# Same targets as Experiment13, but svc-noisy is pinned to worker-1
# (separate ztunnel from DSB victim services on worker-0).
# This is the control / isolation variant.
#
# Usage: make <target> [CASE=A|B|C] [REPS=3]

ROOT    := $(shell pwd)
WRK2    ?= $(ROOT)/../../../wrk2/wrk
PYTHON  := $(ROOT)/.venv/bin/python3
CASE    ?= A
REPS    ?= 3
NOISY_RPS ?= 200
BASELINE := $(ROOT)/../../../Experiment12/results/tables/summary.csv

.PHONY: all setup check-venv verify noisy noisy-remove smoke \
        run-ramp run-burst run-churn run-all-A \
        parse parse-traces amplification analyze figures \
        clean-noisy clean help

all: help

# ─────────────────────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────────────────────
setup:
	bash scripts/utils/setup-venv.sh

check-venv:
	$(PYTHON) -c "import matplotlib, numpy, pandas, scipy; print('[OK] venv imports working')"

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOY
# ─────────────────────────────────────────────────────────────────────────────
verify:
	@echo "[INFO] Checking DSB pods..."
	kubectl cluster-info
	kubectl get pods -n dsb-exp
	kubectl get pods -n dsb-exp -o wide | grep social-graph

## Deploy svc-noisy on WORKER-1 (separate ztunnel — this is the Variant)
noisy:
	kubectl apply -f configs/noisy-neighbor/svc-noisy-deploy.yaml
	kubectl wait --for=condition=Ready pod -l app=svc-noisy         -n dsb-exp --timeout=120s
	kubectl wait --for=condition=Ready pod -l app=svc-noisy-backend -n dsb-exp --timeout=120s
	@echo "[OK] svc-noisy deployed on worker-1. Verify:"
	kubectl get pods -n dsb-exp -o wide | grep svc-noisy

noisy-remove:
	kubectl delete -f configs/noisy-neighbor/svc-noisy-deploy.yaml --ignore-not-found
	kubectl get pods -n dsb-exp | grep noisy || echo "[OK] noisy pods removed"

# ─────────────────────────────────────────────────────────────────────────────
# EXPERIMENT EXECUTION
# ─────────────────────────────────────────────────────────────────────────────
smoke:
	WRK2=$(WRK2) bash scripts/run/run-experiment.sh \
	  --case A --mode sustained-ramp --noisy-rps 200

run-ramp:
	WRK2=$(WRK2) bash scripts/run/run-sustained-ramp.sh --case $(CASE) --reps $(REPS)

run-burst:
	for i in 1 2 3; do \
	  WRK2=$(WRK2) bash scripts/run/run-experiment.sh --case $(CASE) --mode burst; \
	  sleep 120; \
	done

run-churn:
	for i in 1 2 3; do \
	  WRK2=$(WRK2) bash scripts/run/run-experiment.sh --case $(CASE) --mode churn; \
	  sleep 120; \
	done

run-all-A:
	$(MAKE) run-ramp  CASE=A REPS=$(REPS)
	$(MAKE) run-burst CASE=A
	$(MAKE) run-churn CASE=A

# ─────────────────────────────────────────────────────────────────────────────
# ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────
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

amplification:
	$(PYTHON) src/analysis/amplification.py \
	  --baseline $(BASELINE) \
	  --data     data/processed/csv/ \
	  --output   results/tables/amplification.csv

analyze: parse parse-traces amplification

# ─────────────────────────────────────────────────────────────────────────────
# FIGURES
# ─────────────────────────────────────────────────────────────────────────────
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
clean-noisy: noisy-remove

clean:
	bash scripts/cleanup/cleanup.sh

# ─────────────────────────────────────────────────────────────────────────────
# HELP
# ─────────────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Experiment 13 — VARIANT (Isolated ztunnel Control)"
	@echo "svc-noisy is on worker-1 (separate ztunnel from DSB victim on worker-0)"
	@echo ""
	@echo "Usage: make <target> [CASE=A|B|C] [REPS=3]"
	@echo ""
	@echo "── Setup ──────────────────────────────────────────────────────────"
	@echo "  setup          Create .venv and install Python dependencies"
	@echo "  check-venv     Verify .venv imports work"
	@echo ""
	@echo "── Deploy ─────────────────────────────────────────────────────────"
	@echo "  verify         Check cluster + DSB pod state"
	@echo "  noisy          Deploy svc-noisy on WORKER-1 (isolated ztunnel)"
	@echo "  noisy-remove   Remove svc-noisy pods"
	@echo ""
	@echo "── Experiment ─────────────────────────────────────────────────────"
	@echo "  smoke          Quick 1-trial test (Case A, 200 RPS noisy)"
	@echo "  run-ramp       Sustained-ramp sweep for CASE"
	@echo "  run-burst      Burst mode 3 reps for CASE"
	@echo "  run-churn      Churn mode 3 reps for CASE"
	@echo "  run-all-A      All modes for Case A"
	@echo ""
	@echo "── Analysis ───────────────────────────────────────────────────────"
	@echo "  parse          Parse wrk2 outputs → CSVs"
	@echo "  parse-traces   Parse Jaeger traces → per-service CSV"
	@echo "  amplification  Compute amplification ratios vs Exp12 baseline"
	@echo "  analyze        parse + parse-traces + amplification"
	@echo ""
	@echo "── Figures ────────────────────────────────────────────────────────"
	@echo "  figures        Generate all figures"
	@echo ""
	@echo "── Cleanup ────────────────────────────────────────────────────────"
	@echo "  clean-noisy    Remove svc-noisy pods"
	@echo "  clean          Full teardown"
	@echo ""
	@echo "Recommended workflow:"
	@echo "  make setup && make verify && make noisy && make smoke"
	@echo "  make run-all-A && make analyze && make figures"
	@echo ""
