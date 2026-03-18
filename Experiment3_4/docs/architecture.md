# Architecture

## Istio Ambient Model

Unlike sidecar mode:

- No per-pod proxies
- Uses node-level proxy → **ztunnel**

---

## Traffic Flow

Client Pod to ztunnel (node-level, as of now no waypoint) to service pod.


---

## Key Property

All pods on a node share:

- Same ztunnel
- Same CPU resources
- Same queues

---

## Experimental Setup
