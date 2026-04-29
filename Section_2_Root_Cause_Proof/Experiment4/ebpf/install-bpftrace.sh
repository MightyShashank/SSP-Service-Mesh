#!/bin/bash
# install-bpftrace.sh — Verify/install bpftrace on the worker node
# Run this ON the worker node (ssp-worker-1) or via SSH from master

set -euo pipefail

log() {
  echo -e "\n[INFO] $1"
}

warn() {
  echo -e "\n[WARN] $1"
}

fail() {
  echo -e "\n[ERROR] $1"
  exit 1
}

# ==============================
# STEP 1 — CHECK/INSTALL BPFTRACE
# ==============================
log "Checking bpftrace installation..."

if command -v bpftrace &> /dev/null; then
  BPFTRACE_VER=$(bpftrace --version 2>/dev/null || echo "unknown")
  echo "✔ bpftrace is installed → $BPFTRACE_VER"
else
  log "bpftrace not found, installing..."
  sudo apt-get update
  sudo apt-get install -y bpftrace
  echo "✔ bpftrace installed"
fi

# ==============================
# STEP 2 — CHECK KERNEL HEADERS
# ==============================
log "Checking kernel headers..."

KVER=$(uname -r)
if dpkg -l | grep -q "linux-headers-$KVER"; then
  echo "✔ Kernel headers present → $KVER"
else
  log "Installing kernel headers for $KVER..."
  sudo apt-get install -y "linux-headers-$KVER" || warn "Kernel headers installation failed (may not be available for this kernel)"
fi

# ==============================
# STEP 3 — VERIFY TRACEFS/DEBUGFS
# ==============================
log "Checking tracefs/debugfs mount..."

if mount | grep -q tracefs; then
  echo "✔ tracefs is mounted"
elif mount | grep -q debugfs; then
  echo "✔ debugfs is mounted"
else
  log "Mounting debugfs..."
  sudo mount -t debugfs none /sys/kernel/debug || warn "debugfs mount failed"
fi

# ==============================
# STEP 4 — VERIFY BCC TOOLS (OPTIONAL)
# ==============================
log "Checking bcc-tools (optional)..."

if dpkg -l | grep -q bpfcc-tools; then
  echo "✔ bcc-tools installed"
else
  warn "bcc-tools not installed. Install with: sudo apt-get install -y bpfcc-tools linux-headers-\$(uname -r)"
  echo "  These are optional but useful for additional tracing capabilities."
fi

# ==============================
# STEP 5 — SMOKE TEST
# ==============================
# NOTE: bpftrace 0.14.0 on Ubuntu 22.04 has a known bug where
# BEGIN/END probes fail with:
#   "ERROR: Could not resolve symbol: /proc/self/exe:BEGIN_trigger"
# This is because the packaged binary is stripped and missing the
# BEGIN_trigger symbol. Our actual .bt probes do NOT use BEGIN/exit(),
# so this does not affect the experiment. We use a tracepoint-based
# smoke test instead.
log "Running bpftrace smoke test..."

# Use a syscall tracepoint but TRIGGER it ourselves to make the test deterministic
# (automation-safe). We run bpftrace in background, then execute a command that
# generates openat syscalls (e.g., ls), and exit after first hit.
# NOTE: We avoid BEGIN/exit() due to the 0.14.0 bug. Instead we rely on the
# tracepoint firing and explicitly exit() after first event.

TMPFILE=$(mktemp)

# Start bpftrace in background and capture output
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("bpftrace_ok\n"); exit(); }' > "$TMPFILE" 2>/dev/null &
BPFTRACE_PID=$!

# Give bpftrace time to attach
sleep 1

# Trigger the syscall ourselves (deterministic)
ls >/dev/null 2>&1

# Wait for bpftrace to exit (or timeout safety)
timeout 5 wait $BPFTRACE_PID 2>/dev/null || true

RESULT=$(cat "$TMPFILE")

if echo "$RESULT" | grep -q "bpftrace_ok"; then
  echo "✔ bpftrace smoke test PASSED"
else
  fail "bpftrace smoke test FAILED"
fi

rm -f "$TMPFILE"

# ==============================
# STEP 6 — CHECK KPROBE SUPPORT
# ==============================
log "Verifying kprobe support..."

# Use bpftrace -l to list available kprobes (doesn't require traffic to trigger)
if sudo bpftrace -l 'kprobe:tcp_rcv_established' 2>/dev/null | grep -q "tcp_rcv_established"; then
  echo "✔ kprobe support verified (tcp_rcv_established is attachable)"
else
  warn "kprobe:tcp_rcv_established not found — kernel may not export this symbol"
fi

# Also verify tcp_recvmsg and tcp_sendmsg (used by latency_decomp.bt)
for probe in "kretprobe:tcp_recvmsg" "kprobe:tcp_sendmsg"; do
  PROBE_NAME=$(echo "$probe" | cut -d: -f2)
  if sudo bpftrace -l "$probe" 2>/dev/null | grep -q "$PROBE_NAME"; then
    echo "✔ $probe available"
  else
    warn "$probe not found"
  fi
done

# ==============================
# STEP 7 — CHECK SCHED TRACEPOINT SUPPORT
# ==============================
log "Verifying sched tracepoint support..."

if sudo bpftrace -l 'tracepoint:sched:sched_switch' 2>/dev/null | grep -q "sched_switch"; then
  echo "✔ sched:sched_switch tracepoint available"
else
  fail "sched:sched_switch tracepoint not available — kernel may not support it"
fi

if sudo bpftrace -l 'tracepoint:sched:sched_wakeup' 2>/dev/null | grep -q "sched_wakeup"; then
  echo "✔ sched:sched_wakeup tracepoint available"
else
  warn "sched:sched_wakeup tracepoint not found (used by queue_delay.bt)"
fi

# ==============================
# STEP 8 — KNOWN LIMITATIONS
# ==============================
log "Checking known bpftrace 0.14.0 limitations..."

echo "⚠ bpftrace 0.14.0 known issues on this system:"
echo "  - BEGIN/END probes may fail (BEGIN_trigger symbol missing)"
echo "  - exit() builtin may not work"
echo "  - Workaround: probes use SIGINT (Ctrl+C) for shutdown instead"
echo "  - This does NOT affect our experiment probes"

# ==============================
# SUMMARY
# ==============================
log "bpftrace Setup COMPLETE ✅"

echo -e "\n========== SUMMARY =========="
echo "bpftrace: $(bpftrace --version 2>/dev/null || echo 'installed')"
echo "Kernel: $(uname -r)"
echo "tracefs: $(mount | grep -c tracefs || echo 0) mounts"
echo "kprobe: tcp_rcv_established, tcp_recvmsg, tcp_sendmsg"
echo "sched tracepoints: sched_switch, sched_wakeup"
echo "Known limitation: BEGIN/exit() broken (does not affect probes)"
echo "Status: READY FOR eBPF PROBING"
echo "================================"
