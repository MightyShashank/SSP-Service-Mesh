# Architecture

## Istio Ambient Model

Unlike sidecar mode:

- No per-pod proxies
- Uses node-level proxy → **ztunnel**

---

## Traffic Flow

```
Client Pod → ztunnel (node-level) → Service Pod
```

---

## ztunnel Internal Pipeline

Requests traverse the following stages inside ztunnel:

```
1. Kernel TCP recv (tcp_rcv_established)
2. Userspace read (tcp_recvmsg → tokio poll_read)
3. Request parsing + routing
4. Queue → scheduler dispatch
5. Handler execution
6. Response write (tcp_sendmsg)
```

Stages 3–5 are the **proxy queue + execution** pipeline where contention occurs.

---

## eBPF Attachment Points

```
                Kernel Space               │          Userspace (ztunnel)
                                           │
  ┌─────────────────┐                      │
  │ tcp_rcv_established ── t1              │
  │       ↓               │               │
  │ tcp_recvmsg ────────── t2 ────────────→│→ poll_read (t2)
  │                        │               │     ↓
  │                        │               │  enqueue (t3)
  │                        │               │     ↓
  │                        │               │  dequeue (t4)
  │                        │               │     ↓
  │ tcp_sendmsg ←──────── t5 ←────────────│← write_response (t5)
  └─────────────────┘                      │
                                           │
  tracepoint:sched:sched_switch            │
  tracepoint:sched:sched_wakeup            │
  (worker thread scheduling)               │
```

---

## Key Property

All pods on a node share:

- Same ztunnel
- Same CPU resources  
- Same queues
- Same worker thread pool

When worker threads are occupied (high occupancy), new requests queue up → tail latency inflation.

---

## Probe Overhead

| Probe Type | Overhead per hit | Impact |
|:-----------|:----------------|:-------|
| kprobe | ~100–500 ns | Negligible |
| kretprobe | ~200–600 ns | Negligible |
| tracepoint | ~100–300 ns | Negligible |
| uprobe (if used) | ~1–5 μs | Minimal |

Total overhead is well below measurement resolution and does not affect results.
