#!/bin/bash

# eBPF Diagnostic Script for kwin_wayland High CPU Usage
# Run with: sudo ./diagnose_kwin.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== kwin_wayland eBPF Diagnostic Script ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (sudo)${NC}"
    exit 1
fi

# Check if kwin_wayland is running
KWIN_PID=$(pgrep -x kwin_wayland 2>/dev/null || true)
if [ -z "$KWIN_PID" ]; then
    echo -e "${RED}Error: kwin_wayland is not running${NC}"
    exit 1
fi
echo -e "${GREEN}Found kwin_wayland with PID: ${KWIN_PID}${NC}"
echo ""

# Check for required tools
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 not found. Install with:${NC}"
        echo "  sudo apt install bpftrace bpfcc-tools linux-headers-\$(uname -r)"
        exit 1
    fi
}

check_tool bpftrace

# Use absolute path for sleep to avoid conda/nodeenv conflicts
SLEEP_BIN="/bin/sleep"
if [ ! -x "$SLEEP_BIN" ]; then
    SLEEP_BIN="/usr/bin/sleep"
fi
echo -e "${GREEN}Using sleep binary: ${SLEEP_BIN}${NC}"

# Create output directory
OUTPUT_DIR="/tmp/kwin_diag_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
echo -e "${GREEN}Output directory: ${OUTPUT_DIR}${NC}"
echo ""

# Duration for each test
DURATION=10

#------------------------------------------------------------------------------
# Step 1: Baseline CPU usage
#------------------------------------------------------------------------------
echo -e "${YELLOW}[1/7] Capturing baseline CPU usage (5 seconds)...${NC}"
top -b -n 5 -d 1 -p "$KWIN_PID" > "$OUTPUT_DIR/01_baseline_cpu.txt" 2>&1 &
TOP_PID=$!
$SLEEP_BIN 5
kill $TOP_PID 2>/dev/null || true
echo "  Saved to: $OUTPUT_DIR/01_baseline_cpu.txt"
cat "$OUTPUT_DIR/01_baseline_cpu.txt" | grep -E "kwin_wayland|%CPU" | tail -10
echo ""

#------------------------------------------------------------------------------
# Step 2: Syscall distribution
#------------------------------------------------------------------------------
echo -e "${YELLOW}[2/7] Profiling syscall distribution (${DURATION}s)...${NC}"
bpftrace -e '
tracepoint:syscalls:sys_enter_* /comm == "kwin_wayland"/ {
    @[probe] = count();
}' -c "$SLEEP_BIN $DURATION" 2>&1 | tee "$OUTPUT_DIR/02_syscall_distribution.txt"
echo ""

#------------------------------------------------------------------------------
# Step 3: DRM/GPU subsystem events
#------------------------------------------------------------------------------
echo -e "${YELLOW}[3/7] Profiling DRM/GPU subsystem (${DURATION}s)...${NC}"
bpftrace -e '
tracepoint:drm:* /comm == "kwin_wayland"/ {
    @[probe] = count();
}' -c "$SLEEP_BIN $DURATION" 2>&1 | tee "$OUTPUT_DIR/03_drm_events.txt"
echo ""

#------------------------------------------------------------------------------
# Step 4: CPU scheduler latency
#------------------------------------------------------------------------------
echo -e "${YELLOW}[4/7] Profiling CPU scheduler latency (${DURATION}s)...${NC}"
bpftrace -e '
tracepoint:sched:sched_switch /prev_comm == "kwin_wayland"/ {
    @off_cpu[prev_state] = count();
}
tracepoint:sched:sched_switch /next_comm == "kwin_wayland"/ {
    @on_cpu = count();
}' -c "$SLEEP_BIN $DURATION" 2>&1 | tee "$OUTPUT_DIR/04_scheduler_latency.txt"
echo ""

#------------------------------------------------------------------------------
# Step 5: ioctl calls (GPU communication)
#------------------------------------------------------------------------------
echo -e "${YELLOW}[5/7] Profiling ioctl calls (${DURATION}s)...${NC}"
bpftrace -e '
tracepoint:syscalls:sys_enter_ioctl /comm == "kwin_wayland"/ {
    @ioctl_cmds[args->cmd] = count();
}' -c "$SLEEP_BIN $DURATION" 2>&1 | tee "$OUTPUT_DIR/05_ioctl_calls.txt"
echo ""

#------------------------------------------------------------------------------
# Step 6: File descriptor activity
#------------------------------------------------------------------------------
echo -e "${YELLOW}[6/7] Profiling file descriptor read/write (${DURATION}s)...${NC}"
bpftrace -e '
tracepoint:syscalls:sys_enter_read /comm == "kwin_wayland"/ {
    @reads[args->fd] = count();
}
tracepoint:syscalls:sys_enter_write /comm == "kwin_wayland"/ {
    @writes[args->fd] = count();
}
tracepoint:syscalls:sys_enter_poll /comm == "kwin_wayland"/ {
    @polls = count();
}
tracepoint:syscalls:sys_enter_epoll_wait /comm == "kwin_wayland"/ {
    @epoll_waits = count();
}' -c "$SLEEP_BIN $DURATION" 2>&1 | tee "$OUTPUT_DIR/06_fd_activity.txt"
echo ""

#------------------------------------------------------------------------------
# Step 7: BCC tools (if available)
#------------------------------------------------------------------------------
echo -e "${YELLOW}[7/7] Running BCC tools (if available)...${NC}"

if [ -f /usr/share/bcc/tools/profile ]; then
    echo "  Running CPU profile..."
    /usr/share/bcc/tools/profile -p "$KWIN_PID" -F 99 10 > "$OUTPUT_DIR/07a_bcc_profile.txt" 2>&1 || true
    echo "  Saved to: $OUTPUT_DIR/07a_bcc_profile.txt"
else
    echo "  BCC profile tool not found, skipping..."
fi

if [ -f /usr/share/bcc/tools/offcputime ]; then
    echo "  Running off-CPU time analysis..."
    timeout 15 /usr/share/bcc/tools/offcputime -p "$KWIN_PID" 10 > "$OUTPUT_DIR/07b_bcc_offcputime.txt" 2>&1 || true
    echo "  Saved to: $OUTPUT_DIR/07b_bcc_offcputime.txt"
else
    echo "  BCC offcputime tool not found, skipping..."
fi

if [ -f /usr/share/bcc/tools/syscount ]; then
    echo "  Running syscall count with latency..."
    /usr/share/bcc/tools/syscount -p "$KWIN_PID" -L 10 > "$OUTPUT_DIR/07c_bcc_syscount.txt" 2>&1 || true
    echo "  Saved to: $OUTPUT_DIR/07c_bcc_syscount.txt"
else
    echo "  BCC syscount tool not found, skipping..."
fi
echo ""

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo -e "${GREEN}=== Diagnostic Complete ===${NC}"
echo ""
echo "All results saved to: $OUTPUT_DIR"
echo ""
echo "Files generated:"
ls -la "$OUTPUT_DIR"
echo ""
echo -e "${YELLOW}Quick Analysis:${NC}"
echo ""

# Show top syscalls
echo "Top 10 syscalls:"
grep -E "^@\[" "$OUTPUT_DIR/02_syscall_distribution.txt" 2>/dev/null | sort -t: -k2 -rn | head -10 || echo "  (no data)"
echo ""

# Show ioctl summary
echo "ioctl command counts:"
grep -E "^@ioctl" "$OUTPUT_DIR/05_ioctl_calls.txt" 2>/dev/null | head -10 || echo "  (no data)"
echo ""

echo -e "${GREEN}To share results, run:${NC}"
echo "  tar -czvf kwin_diag.tar.gz $OUTPUT_DIR"
echo ""
