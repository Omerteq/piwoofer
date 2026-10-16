#!/bin/bash
# Make the root filesystem read-only (RAM overlay) so pulling the plug cannot corrupt the SD card.
# Kök dosya sistemini salt okunur yapar (RAM overlay); fişi çekmek SD kartı bozmaz.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root / root olarak çalıştır"; exit 1; }
raspi-config nonint enable_overlayfs
sync
echo "Overlay enabled. Reboot to apply: sudo reboot"
echo "Overlay açıldı. Uygulamak için reboot at: sudo reboot"
