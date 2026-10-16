#!/bin/bash
# Turn the read-only overlay off so you can change settings. Re-enable with enable-readonly.sh afterwards.
# Ayar değiştirebilmek için salt okunur overlay'i kapatır. Sonra enable-readonly.sh ile tekrar aç.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root / root olarak çalıştır"; exit 1; }
raspi-config nonint disable_overlayfs
sync
echo "Overlay disabled. Reboot to apply: sudo reboot"
echo "Overlay kapatıldı. Uygulamak için reboot at: sudo reboot"
