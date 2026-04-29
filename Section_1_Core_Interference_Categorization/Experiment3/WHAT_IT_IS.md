# Experiment 3 — What Is This?

## One-Line Summary
**Synthetic shared-ztunnel interference: does a noisy neighbor on the same node blow up tail latency for a latency-sensitive service?**

## The Point
This is the **core interference discovery experiment** for Section 1.
It establishes the fundamental phenomenon that everything else in the paper is built on:
when two services share the **same ztunnel instance** on the same Kubernetes node under
Istio Ambient Mesh, the noisy one causes **tail-latency amplification** in the
latency-sensitive one — even though they are completely separate microservices with
no code-level coupling.

The key insight: ztunnel is a **shared, node-level resource**. It is not per-pod.
Every pod on a node competes for the same proxy worker threads.

---

## What Is Running
| Component | Role |
|-----------|------|
| **svc-a** | Latency-sensitive victim — receives measured load at fixed QPS |
| **svc-b** | Noisy neighbor — generates configurable background load via ztunnel |
| **client** | In-cluster Fortio load generator — fixed QPS, not best-effort |
| **Istio Ambient** | `istio.io/dataplane-mode=ambient` on namespace — ztunnel handles all traffic |

All three pods are **co-located on the same node** via `nodeSelector`, guaranteeing
they share a single ztunnel process.

---

## What Is Measured
- **End-to-end latency** for svc-a requests (P50, P99, P99.9) at fixed QPS
- **With and without** svc-b background load
- **Multiple svc-b load levels** to quantify amplification as a function of interference intensity
- **ztunnel CPU** from Prometheus during load

The amplification in svc-a's tail latency **as svc-b load increases** is the main result.
It cannot be explained by application-level effects — it is purely a ztunnel contention artifact.

---

## Node Layout
```
single-node  ← svc-a + svc-b + client + ztunnel (all on same node, by design)
```
This is the minimal setup to trigger and observe the effect.

---

## Analysis Levels
| Level | What it shows |
|-------|--------------|
| `make run-lvl1` | Raw latency distributions per load level |
| `make run-lvl2` | P99 amplification vs svc-b load curve |
| `make run-lvl3` | ztunnel CPU vs latency correlation |

---

## Relationship to Other Experiments

```
Exp 3  (Synthetic: shared-ztunnel interference found)   ← YOU ARE HERE
   ↓ "but WHY exactly does the proxy cause this?"
Exp 4  (eBPF: causal decomposition inside ztunnel)
   ↓ "does this happen in real workloads too?"
Exp 12 (DSB Social Network: Istio Ambient baseline)
Exp 13 (DSB Social Network: noisy-neighbor at scale)
```

---

## Quick Commands
```bash
cd scripts
bash deploy.sh               # deploy svc-a + svc-b + client on same node
bash run-experiment.sh       # run load sweep
make build && make run-lvl1 RUN_ID=<id>  # analyze results
```
