# Methodology

## Traffic Generation

Tool: `Fortio`

Traffic originates from:

- Client pod inside cluster
- Same node as services

This ensures:
- No external network noise
- All traffic flows through the same **ztunnel (node-level dataplane)**

---

## eBPF Instrumentation

Tool: `bpftrace` (v0.14.0)

Probes run on the **worker node** (`ssp-worker-1`) with sudo.

### Probe Types Used

| Probe Type | Target | Purpose |
|:-----------|:-------|:--------|
| `kprobe:tcp_rcv_established` | Kernel TCP | Packet arrival time ($t_1$) |
| `kretprobe:tcp_recvmsg` | Kernel TCP | Userspace delivery time ($t_2$) |
| `kprobe:tcp_sendmsg` | Kernel TCP | Response write time ($t_5$) |
| `tracepoint:sched:sched_switch` | Scheduler | Worker on/off CPU time |
| `tracepoint:sched:sched_wakeup` | Scheduler | Worker wakeup time |

### Probe Filtering

All probes are filtered by ztunnel PID or comm name to avoid capturing unrelated traffic:

```
kprobe:tcp_rcv_established /pid == $ZTUNNEL_PID/ { ... }
tracepoint:sched:sched_switch /args->prev_comm == "ztunnel"/ { ... }
```

---

## Latency Decomposition

For each request, we capture timestamps and decompose latency:

```
T_network     = t2 - t1   (kernel → userspace)
T_proxy_total = t5 - t2   (total proxy processing)
```

With debug symbols (if available):
```
T_kernel_queue = t3 - t2
T_proxy_queue  = t4 - t3
T_execution    = t5 - t4
```

---

## Worker Occupancy Measurement

Computed from scheduler tracepoints:

```
occupancy = on_cpu_time / (on_cpu_time + off_cpu_time)
```

Per-thread measurements aggregated over ztunnel worker threads.

---

## Phases

### 1. Warmup
- Duration: 60s
- Purpose: stabilize system (connection reuse, cache warmup)

---

### 2. Per-Load-Level Experiment

For each svc-B load ∈ {0, 100, 500, 1000} RPS:

```
1. Start 3 eBPF probes (background)
2. Run Fortio: svc-A @ 100 RPS + svc-B @ load RPS for 120s
3. Stop eBPF probes (SIGINT → triggers END summary)
4. Save all outputs
5. Cooldown (60s + CPU check)
```

---

## Metrics Collected

### eBPF-level
- Per-request latency decomposition (T_network, T_proxy_total)
- Per-thread CPU occupancy (on/off CPU time)
- Scheduling delay (proxy queue approximation)
- Histograms at P50, P99, P99.99

### Application-level (Fortio)
- Latency percentiles: P50, P90, P99, P99.9
- Throughput (Actual QPS)
- Error rate

### System-level
- ztunnel CPU usage
- Node CPU usage
- Pod CPU usage

Collected via:
```
kubectl top
```

---

## Visualizations (8 total)

1. Stacked Latency Breakdown vs. Load
2. Latency Component Distributions (Histograms)
3. Proxy Queue Delay vs. svc-B Load
4. Worker Occupancy vs. Queue Delay (Correlation Plot)
5. CPU Utilization vs. End-to-End Latency
6. Head-of-Line Blocking Timeline
7. Queue Delay vs. Execution Time (Decoupling Plot)
8. Baseline vs. Interference Comparison

---

## Repetition

- Each experiment repeated **3–5 times**
- Results from eBPF require high sample counts per run (120s × 100+ RPS = 12,000+ samples minimum)

---

## Controls

- Fixed replicas (1 each)
- No autoscaling
- No background workloads
- Same node placement (enforced via nodeSelector)
- Same namespace (ambient mesh enabled)
- eBPF probe overhead < 5μs per event (negligible)

---

## Key Advantage of eBPF

Unlike external measurement tools, eBPF provides:

- **Zero-cost instrumentation** (no application modification)
- **Nanosecond-precision timestamps** (monotonic clock)
- **Per-request granularity** (not aggregated averages)
- **Cross-layer visibility** (kernel + userspace + scheduler)
- **Causal evidence** (not just correlation)
