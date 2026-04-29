# What This Variant Is

## The One Change: Where Does `svc-noisy` Live?

| | Experiment 13 (Original) | Variant (This folder) |
|---|---|---|
| `svc-noisy` node | **worker-0** | **worker-1** |
| `svc-noisy-backend` node | **worker-0** | **worker-1** |
| DSB victim services node | worker-0 | worker-0 (unchanged) |
| ztunnel shared with victim? | **YES** | **NO** |

Everything else — DSB load rates, measurement duration, RPS ramp levels, repetitions, all analysis scripts — is **identical** to Experiment 13.

---

## Why This Matters: ztunnel is Per-Node

In Istio Ambient Mesh, the `ztunnel` proxy is a **DaemonSet** — one instance per node. Every pod on a node shares that node's ztunnel for all its L4 mTLS proxying. It is not per-pod or per-service. This is the core architecture:

```
                worker-0                         worker-1
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│  social-graph-service  (victim) │  │  home-timeline-service          │
│  user-service                   │  │  compose-post-service           │
│  text-service                   │  │  post-storage-service           │
│                                 │  │                                 │
│  ███ ztunnel-worker0 ███        │  │  ███ ztunnel-worker1 ███        │
│  (shared proxy for ALL pods)    │  │  (shared proxy for ALL pods)    │
│                                 │  │                                 │
│  svc-noisy       ← Exp 13 only  │  │  svc-noisy  ← Variant only     │
│  svc-noisy-backend ← Exp 13     │  │  svc-noisy-backend ← Variant   │
└─────────────────────────────────┘  └─────────────────────────────────┘
```

### In Experiment 13 (original):
`svc-noisy` generates heavy traffic → all that traffic flows through `ztunnel-worker0` → the exact same ztunnel that handles `social-graph-service`, `user-service`, etc. → CPU contention in ztunnel → DSB requests queue longer → **tail latency spikes**.

### In This Variant:
`svc-noisy` generates identical heavy traffic → flows through `ztunnel-worker1` → an entirely separate ztunnel instance from the one handling DSB victim services → **no contention** → DSB tail latency should remain at baseline levels.

---

## What This Variant Proves

This is the **null hypothesis / control experiment**. It answers the question:

> *"Is the latency degradation we saw in Experiment 13 actually caused by the shared ztunnel, or just by general cluster load?"*

If the Variant shows **no significant latency amplification** even at the same high noisy-RPS levels, it proves:
- The interference in Experiment 13 was **ztunnel-specific**, not generic cluster saturation.
- The ztunnel DaemonSet architecture creates **de facto resource coupling** between unrelated services that happen to share a node.
- Workload placement (node affinity) is a **first-class concern** for latency isolation in Ambient Mesh.

---

## Expected Results Compared to Experiment 13

| Noisy RPS | Exp 13 compose-post P99.9 | Variant compose-post P99.9 |
|-----------|--------------------------|---------------------------|
| 0         | ~826 ms (baseline)        | ~826 ms (baseline)         |
| 200       | ~1.5–2.5×                 | ~1.0–1.1× (near baseline)  |
| 500       | ~3–6×                     | ~1.0–1.2×                  |
| 700       | ~5–9×                     | ~1.0–1.3×                  |

If the Variant shows near-zero amplification (≤1.2×) at all RPS levels, it conclusively isolates the mechanism to ztunnel sharing.

---

## Summary in One Line

> Experiment 13 puts the noisy neighbor on the **same ztunnel** as the victim (maximises contention).
> This Variant puts it on a **different ztunnel** (eliminates contention) — as a control to prove the effect is ztunnel-specific.
