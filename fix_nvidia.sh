#!/bin/bash
# Restore NVIDIA packages to 575.57.08-1
# Run with: sudo ./fix_nvidia.sh

set -e

apt install -y --allow-downgrades \
  libcuda1=575.57.08-1 \
  libnvcuvid1=575.57.08-1 \
  libnvidia-vksc-core=575.57.08-1 \
  nvidia-driver=575.57.08-1 \
  nvidia-driver-libs=575.57.08-1 \
  xserver-xorg-video-nvidia=575.57.08-1 \
  nvidia-kernel-dkms=575.57.08-1 \
  nvidia-kernel-support=575.57.08-1 \
  libnvidia-allocator1=575.57.08-1 \
  libnvidia-api1=575.57.08-1 \
  libnvidia-cfg1=575.57.08-1 \
  libnvidia-encode1=575.57.08-1 \
  libnvidia-glvkspirv=575.57.08-1 \
  libnvidia-gpucomp=575.57.08-1 \
  libnvidia-ngx1=575.57.08-1 \
  libnvidia-pkcs11-openssl3=575.57.08-1 \
  libnvidia-ptxjitcompiler1=575.57.08-1 \
  libnvidia-rtcore=575.57.08-1 \
  libnvidia-glcore=575.57.08-1 \
  libnvidia-eglcore=575.57.08-1 \
  libglx-nvidia0=575.57.08-1 \
  libegl-nvidia0=575.57.08-1 \
  libgles-nvidia1=575.57.08-1 \
  libgles-nvidia2=575.57.08-1 \
  nvidia-egl-icd=575.57.08-1 \
  nvidia-vulkan-icd=575.57.08-1 \
  nvidia-modprobe=575.57.08-1 \
  nvidia-persistenced=575.57.08-1 \
  nvidia-vdpau-driver=575.57.08-1 \
  firmware-nvidia-gsp=575.57.08-1

echo "Done. Please reboot your system."
