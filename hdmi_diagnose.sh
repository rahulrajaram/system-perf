#!/bin/bash
#
# hdmi_diagnose.sh - Diagnose HDMI detection issues on hybrid Intel/NVIDIA laptops
#
# This script checks the state of all display outputs, GPU power management,
# NVIDIA driver versions, and kernel logs to help identify why an HDMI monitor
# connected to the NVIDIA GPU is not being detected.
#
# No changes are made to the system. Safe to run at any time.
#
# Usage: ./hdmi_diagnose.sh
#
# Context:
#   - Laptop has Intel UHD (card0) + NVIDIA RTX 4060 (card1)
#   - Physical HDMI port is wired to the NVIDIA GPU (HDMI-1-0 in xrandr)
#   - PRIME Render Offload mode (Intel primary, NVIDIA offload)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== HDMI Display Diagnostic ===${NC}"
echo "Date: $(date)"
echo ""

# ---- 1. xrandr output status ----
echo -e "${CYAN}[1/6] Display outputs (xrandr)${NC}"
xrandr | grep -E 'connected|HDMI'
echo ""

# ---- 2. NVIDIA GPU power state ----
echo -e "${CYAN}[2/6] NVIDIA GPU power management${NC}"
NVIDIA_PCI="0000:01:00.0"
if [ -d "/sys/bus/pci/devices/$NVIDIA_PCI" ]; then
    RUNTIME_STATUS=$(cat "/sys/bus/pci/devices/$NVIDIA_PCI/power/runtime_status" 2>/dev/null || echo "unknown")
    POWER_CONTROL=$(cat "/sys/bus/pci/devices/$NVIDIA_PCI/power/control" 2>/dev/null || echo "unknown")
    echo "  PCI device:     $NVIDIA_PCI"
    echo "  runtime_status: $RUNTIME_STATUS"
    echo "  power/control:  $POWER_CONTROL"

    if [ "$RUNTIME_STATUS" = "suspended" ]; then
        echo -e "  ${RED}GPU is SUSPENDED - HDMI detection will fail${NC}"
        echo -e "  ${YELLOW}Fix: echo \"on\" | sudo tee /sys/bus/pci/devices/$NVIDIA_PCI/power/control${NC}"
    elif [ "$POWER_CONTROL" = "auto" ]; then
        echo -e "  ${YELLOW}GPU power is 'auto' - may suspend and lose HDMI${NC}"
    else
        echo -e "  ${GREEN}GPU is active and power is forced on${NC}"
    fi
else
    echo -e "  ${RED}PCI device $NVIDIA_PCI not found${NC}"
fi
echo ""

# ---- 3. NVIDIA driver version check ----
echo -e "${CYAN}[3/6] NVIDIA driver versions${NC}"
if [ -f /proc/driver/nvidia/version ]; then
    KMOD_VER=$(grep "Kernel Module" /proc/driver/nvidia/version | grep -oP '\d+\.\d+\.\d+')
    echo "  Kernel module:  $KMOD_VER"
else
    echo "  Kernel module:  not loaded"
fi

if command -v nvidia-smi &>/dev/null; then
    SMI_PATH=$(command -v nvidia-smi)
    SMI_HEADER=$(nvidia-smi 2>/dev/null | head -3 || true)
    SMI_VER=$(echo "$SMI_HEADER" | grep -oP 'NVIDIA-SMI \K[\d.]+' || echo "unknown")
    DRV_VER=$(echo "$SMI_HEADER" | grep -oP 'Driver Version: \K[\d.]+' || echo "unknown")
    echo "  nvidia-smi bin: $SMI_PATH (tool v$SMI_VER)"
    echo "  Driver version: $DRV_VER"

    if [ "$SMI_VER" != "$DRV_VER" ]; then
        echo -e "  ${YELLOW}nvidia-smi tool version ($SMI_VER) differs from driver ($DRV_VER)${NC}"
        echo -e "  ${YELLOW}Likely a stale binary at $SMI_PATH from an old manual install${NC}"
    fi
fi
echo ""

# ---- 4. NVIDIA kernel modules loaded ----
echo -e "${CYAN}[4/6] NVIDIA kernel modules${NC}"
lsmod | grep -E '^nvidia' || echo "  No nvidia modules loaded"
echo ""

# ---- 5. Xorg log - NVIDIA output status ----
echo -e "${CYAN}[5/6] Xorg log - NVIDIA DFP outputs${NC}"
XLOG="/var/log/Xorg.0.log"
if [ -f "$XLOG" ]; then
    grep -E 'NVIDIA.*DFP-[0-9]+:' "$XLOG" | tail -12
else
    echo "  $XLOG not found"
fi
echo ""

# ---- 6. GRUB NVIDIA parameters ----
echo -e "${CYAN}[6/6] GRUB NVIDIA kernel parameters${NC}"
GRUB_FILE="/etc/default/grub"
if [ -f "$GRUB_FILE" ]; then
    CMDLINE=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT' "$GRUB_FILE" || true)
    echo "  $CMDLINE"

    if echo "$CMDLINE" | grep -q 'nvidia-drm.modeset=1'; then
        echo -e "  ${GREEN}nvidia-drm.modeset=1 is set${NC}"
    else
        echo -e "  ${YELLOW}nvidia-drm.modeset=1 is NOT set${NC}"
    fi

    if echo "$CMDLINE" | grep -q 'NVreg_DynamicPowerManagement=0x00'; then
        echo -e "  ${GREEN}Dynamic power management is disabled (good for HDMI)${NC}"
    else
        echo -e "  ${YELLOW}NVreg_DynamicPowerManagement not set - GPU may suspend${NC}"
    fi
else
    echo "  $GRUB_FILE not found"
fi
echo ""

# ---- Summary ----
echo -e "${GREEN}=== Summary ===${NC}"
HDMI_STATUS=$(xrandr 2>/dev/null | grep 'HDMI-1-0' | awk '{print $2}')
if [ "$HDMI_STATUS" = "connected" ]; then
    echo -e "  HDMI-1-0: ${GREEN}CONNECTED${NC}"
    ACTIVE=$(xrandr --listmonitors 2>/dev/null | grep 'HDMI-1-0' || true)
    if [ -n "$ACTIVE" ]; then
        echo -e "  Status:   ${GREEN}Active (displaying)${NC}"
    else
        echo -e "  Status:   ${YELLOW}Connected but not active${NC}"
        echo -e "  Activate: xrandr --output HDMI-1-0 --auto --right-of DP-2"
    fi
else
    echo -e "  HDMI-1-0: ${RED}DISCONNECTED${NC}"
    echo ""
    echo "  Suggested fixes (in order):"
    echo "  1. Force GPU power on:"
    echo "     echo \"on\" | sudo tee /sys/bus/pci/devices/$NVIDIA_PCI/power/control"
    echo "  2. Reload NVIDIA modules (kills X session!):"
    echo "     sudo ./hdmi_fix_reload.sh"
    echo "  3. Reboot"
fi
echo ""
