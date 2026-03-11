#!/bin/bash
# GPU Diagnostic Script
# Run with: sudo ./gpu_diagnostic.sh

echo "=== GPU DIAGNOSTIC REPORT ==="
echo "Date: $(date)"
echo ""

echo "=== 1. PCI GPU Devices ==="
lspci | grep -iE 'vga|3d|display'
echo ""

echo "=== 2. NVIDIA Driver Status ==="
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi
else
    echo "nvidia-smi not found in PATH"
    echo "Searching for nvidia-smi..."
    find /usr -name "nvidia-smi" 2>/dev/null
fi
echo ""

echo "=== 3. Loaded GPU Kernel Modules ==="
lsmod | grep -iE 'nvidia|nouveau|amd|radeon|i915'
echo ""

echo "=== 4. NVIDIA Kernel Messages (dmesg) ==="
dmesg | grep -i nvidia | tail -30
echo ""

echo "=== 5. GPU Errors in dmesg ==="
dmesg | grep -iE 'gpu|graphics|drm' | grep -iE 'error|fail|warn' | tail -20
echo ""

echo "=== 6. Installed NVIDIA Packages ==="
if command -v dpkg &> /dev/null; then
    dpkg -l | grep -i nvidia
elif command -v rpm &> /dev/null; then
    rpm -qa | grep -i nvidia
fi
echo ""

echo "=== 7. NVIDIA Device Files ==="
ls -la /dev/nvidia* 2>/dev/null || echo "No /dev/nvidia* devices found"
echo ""

echo "=== 8. Prime/Optimus Status ==="
if command -v prime-select &> /dev/null; then
    prime-select query
else
    echo "prime-select not available"
fi
echo ""

echo "=== 9. OpenGL Renderer ==="
if command -v glxinfo &> /dev/null; then
    glxinfo | grep -iE 'renderer|vendor|version' | head -5
else
    echo "glxinfo not available (install mesa-utils)"
fi
echo ""

echo "=== 10. CUDA Version ==="
if [ -f /usr/local/cuda/version.txt ]; then
    cat /usr/local/cuda/version.txt
elif command -v nvcc &> /dev/null; then
    nvcc --version
else
    echo "CUDA version file not found, checking packages..."
    dpkg -l 2>/dev/null | grep -i "cuda-toolkit\|cuda-runtime" | head -5
fi
echo ""

echo "=== END OF REPORT ==="
