# Experiment 4 — What Is This?

## One-Line Summary
**eBPF inside ztunnel: proving that tail-latency amplification is caused by proxy queue delay, not the network.**

## The Point
This is the **root-cause proof** for Section 2.
Experiment 3 showed *that* shared-ztunnel contention amplifies tail latency.
Experiment 4 answers *why* — using **eBPF instrumentation** to decompose the full
end-to-end latency of each request into five timestamped pipeline stages inside ztunnel,
pinpointing **proxy queue delay** as the causal factor.

The smoking gun: the correlation between **ztunnel worker thread CPU occupancy** and
**proxy queue delay** is strong. Network congestion, kernel buffering, and application
processing are ruled out by measuring each independently.

Without this experiment, the interference observed in Experiment 3 could be dismissed
as a kernel or network artifact. With it, the causal chain is complete.

---

## What Is Running
| Component | Role |
|-----------|------|
| **svc-a** | Latency-sensitive victim — 100 RPS fixed |
| **svc-b** | Noisy neighbor — swept at `{0, 100, 500, 1000}` RPS |
| **client** | In-cluster Fortio load generator |
| **eBPF probes** | `bpftrace` scripts attached to ztunnel — zero app modification |
| **Istio Ambient** | Same-node placement, shared ztunnel instance |

---

## The Five-Timestamp Decomposition
Every request through ztunnel is sliced into 5 pipeline segments:

```
t1  Packet arrives at kernel TCP stack
t2  Bytes delivered to ztunnel userspace
t3  Request enqueued into proxy service queue      ← queue delay = t4 - t3
t4  Request dequeued, begins execution
t5  Response written to socket
```

**Queue delay (t4 − t3)** is the component that grows with svc-b load.
All other segments (`t2−t1`, `t3−t2`, `t5−t4`) remain flat — ruling out
network, kernel, and application causes.

---

## What Is Measured
| Metric | Source |
|--------|--------|
| Per-segment latency for every request | eBPF kprobes / uprobes on ztunnel |
| Worker thread scheduling statistics | eBPF `sched` tracepoints |
| CPU occupancy vs queue delay correlation | Computed in analysis |
| P99 amplification at each svc-b load level | Fortio output |

---

## Node Layout
```
single-node  ← svc-a + svc-b + client + ztunnel (all co-located, by design)
```
Same layout as Experiment 3 — inter-node effects are eliminated by construction.

---

## Analysis Levels
| Level | What it shows |
|-------|--------------|
| `make run-lvl1` | Stacked latency breakdown + component histograms |
| `make run-lvl2` | Proxy queue delay vs load + worker occupancy correlation |
| `make run-lvl3` | HoL-blocking timeline + CPU–latency decoupling proof |
| `make run-lvl4` | Summary comparison: baseline vs interference across all metrics |

---

## Relationship to Other Experiments

```
Exp 3  (Synthetic: interference observed)
   ↓ "but WHY inside the proxy?"
Exp 4  (eBPF: causal decomposition)             ← YOU ARE HERE
   ↓ "does queue delay actually matter in real workloads?"
Exp 12 (DSB: Istio Ambient baseline — ztunnel overhead at scale)
Exp 13 (DSB: noisy-neighbor — same queue delay mechanism, real microservices)
```

---

## Quick Commands
```bash
cd scripts
bash deploy-setup.sh         # deploy svc-a + svc-b + client on same node

cd ebpf
bash install-bpftrace.sh     # verify eBPF tooling

cd ..
bash scripts/run-experiment.sh          # run with eBPF probes active

make build
make run-lvl1 RUN_ID=<id>   # latency decomposition
make run-lvl2 RUN_ID=<id>   # queue delay correlation
make run-lvl3 RUN_ID=<id>   # HoL blocking proof
make run-lvl4 RUN_ID=<id>   # full summary
```
