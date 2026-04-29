# Architecture — Experiment 12: DeathStarBench Baseline

## Istio Ambient Model

Unlike sidecar mode:

- No per-pod proxies
- Uses node-level proxy → **ztunnel** (one DaemonSet pod per node)
- All traffic for every pod on a node is intercepted by a single shared ztunnel

---

## Traffic Flow (Ambient Mode, No Waypoint)

```
wrk2 (load-gen node)
    │
    │  HTTP/1.1 request to NGINX ClusterIP
    ▼
NGINX frontend pod (worker-1)
    │
    │  Internal HTTP call → ztunnel (worker-1) → HBONE tunnel → ztunnel (worker-0)
    ▼
Victim-tier service pod (worker-0)
e.g., social-graph, user-service, media-service
```

- HBONE (HTTP-Based Overlay Network Encapsulation): HTTP/2-based tunnel between ztunnel instances
- mTLS: enforced transparently by ztunnel using SPIFFE identity (no app changes)
- No Waypoint proxy in this experiment — L4 ambient only (ztunnel handles mTLS + forwarding)

---

## Cluster Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                       │
│                                                                  │
│  ┌──────────────────────────┐  ┌───────────────────────────┐   │
│  │       worker-0           │  │        worker-1            │   │
│  │  (4 vCPU, 8 GB RAM)      │  │   (4 vCPU, 8 GB RAM)      │   │
│  │                          │  │                            │   │
│  │  ┌──────────────────┐    │  │  ┌────────────────────┐   │   │
│  │  │  social-graph    │    │  │  │  nginx-frontend     │   │   │
│  │  │  user-service    │    │  │  │  compose-post-svc  │   │   │
│  │  │  media-service   │ ◄──┼──┼──│  post-storage      │   │   │
│  │  │  url-shorten     │    │  │  │  home-timeline     │   │   │
│  │  │  text-filter     │    │  │  │  user-timeline     │   │   │
│  │  └──────────────────┘    │  │  │  MongoDB ×3        │   │   │
│  │                          │  │  │  Redis ×2          │   │   │
│  │  ┌──────────────────┐    │  │  │  Jaeger (tracing)  │   │   │
│  │  │  ztunnel (shared)│    │  │  └────────────────────┘   │   │
│  │  └──────────────────┘    │  │                            │   │
│  └──────────────────────────┘  │  ┌────────────────────┐   │   │
│                                 │  │  ztunnel (shared)  │   │   │
│  ┌──────────────────────────┐  │  └────────────────────┘   │   │
│  │       load-gen           │  └───────────────────────────┘   │
│  │  (4 vCPU, 8 GB RAM)      │                                  │
│  │                          │                                  │
│  │  ┌──────────────────┐    │                                  │
│  │  │  wrk2 (×3 inst.) │    │                                  │
│  │  │  cpuset-isolated  │    │                                  │
│  │  └──────────────────┘    │                                  │
│  └──────────────────────────┘                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Property for This Experiment

All victim-tier pods on `worker-0` share:

- Same ztunnel instance (one DaemonSet pod)
- Same CPU resources (4 vCPU budget)
- Same async task queues inside ztunnel
- Same Tokio worker thread pool inside ztunnel

In Experiment 12 (this baseline): **no noisy neighbor** is co-located on `worker-0`. The shared ztunnel handles only DSB victim-tier traffic — clean, uncontested execution.

In Experiment 13: `svc-noisy` is added to `worker-0`, sharing the same ztunnel → interference begins.

---

## DeathStarBench Social-Network Call Graph

For `compose-post` (deepest write path):
```
nginx-frontend
    └── compose-post-service
            ├── social-graph-service   ← on worker-0 (victim)
            ├── user-service           ← on worker-0 (victim)
            ├── media-service          ← on worker-0 (victim)
            ├── url-shorten-service    ← on worker-0 (victim)
            ├── text-filter-service    ← on worker-0 (victim)
            ├── post-storage-service   ← on worker-1
            └── home-timeline-service  ← on worker-1
```

For `read-home-timeline` (fanout read):
```
nginx-frontend
    └── home-timeline-service
            └── social-graph-service   ← on worker-0 (victim)
            └── post-storage-service   ← on worker-1
```

For `read-user-timeline` (shallow read):
```
nginx-frontend
    └── user-timeline-service
            └── user-service           ← on worker-0 (victim)
```

---

## ztunnel's Role in the Interference Problem

When `svc-noisy` is added (Exp 13), all traffic — DSB victim-tier **and** noisy neighbor — is handled by the single ztunnel DaemonSet pod on `worker-0`.

Inside ztunnel:
- **HBONE multiplexes** all service streams over shared HTTP/2 connections
- **Tokio async runtime** queues tasks from all services in a single global FIFO queue
- **No per-service scheduling isolation** in stock ztunnel

Result: a burst of noisy traffic fills the shared task queue → DSB victim-tier tasks queue behind noisy tasks → P99.99 tail latency inflates.

**Experiment 12 establishes the before-interference reference** against which this degradation is measured.

---

## Observability Architecture

```
wrk2 → measures end-to-end latency (client-side, open-loop)
       captures: P50, P95, P99, P99.9, P99.99

Jaeger → distributed traces (per-hop span latency)
          deployed on worker-1, sampling 100% during baseline
          captures: per-service span duration inside compose-post call chain

/proc/{pid}/task/{tid}/stat → ztunnel per-thread CPU
                              polled every 1s from worker-0

/proc/{pid}/smaps_rollup → ztunnel RSS
                           polled every 5s from worker-0

kubectl top → coarse node + pod CPU (supplemental)
```
