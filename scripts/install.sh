#!/bin/bash
# Piwoofer installer - turns a Raspberry Pi into a plug-and-play Bluetooth (A2DP) speaker receiver.
# Piwoofer kurulum betiği - Raspberry Pi'yi tak-çalıştır bir Bluetooth (A2DP) ses alıcısına çevirir.
#
# Usage / Kullanım:
#   sudo PIN=1234 NAME=Piwoofer ./install.sh
#
# Must be run with the read-only overlay DISABLED (see README).
# Salt okunur overlay KAPALIYKEN çalıştırılmalıdır (README'ye bak).
set -euo pipefail

PIN="${PIN:-0000}"                   # pairing PIN / eşleşme PIN'i
NAME="${NAME:-Piwoofer}"             # Bluetooth name / Bluetooth adı
ALSA_CARD="${ALSA_CARD:-Headphones}" # `aplay -l` card name (3.5mm jack = Headphones) / ses kartı adı
VOLUME="${VOLUME:-90%}"              # analog output level at boot / açılışta analog çıkış seviyesi
BUFFER_US="${BUFFER_US:-100000}"     # playback buffer (lower = less latency) / tampon (düşük = az gecikme)
PERIOD_US="${PERIOD_US:-25000}"
DISABLE_WIFI="${DISABLE_WIFI:-0}"    # 1 = disable Wi-Fi (use Ethernet) / 1 = Wi-Fi'ı kapat
BT_IMG_MB="${BT_IMG_MB:-16}"

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo). / root olarak çalıştır (sudo)."; exit 1; }
if grep -q 'overlayroot' /proc/cmdline; then
  echo "Read-only overlay is active. Run scripts/disable-readonly.sh and reboot first."
  echo "Salt okunur overlay aktif. Önce scripts/disable-readonly.sh çalıştırıp reboot at."
  exit 1
fi

echo "==> Packages / Paketler"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  bluez bluez-tools bluez-alsa-utils alsa-utils rfkill

echo "==> /etc/bluetooth/main.conf"
sed -i -e '/^#\?Name *=/d' -e '/^#\?Class *=/d' -e '/^#\?DiscoverableTimeout *=/d' \
       -e '/^#\?PairableTimeout *=/d' -e '/^#\?AlwaysPairable *=/d' -e '/^#\?AutoEnable *=/d' \
       /etc/bluetooth/main.conf
sed -i "/^\[General\]/a Name = $NAME\nClass = 0x240414\nDiscoverableTimeout = 0\nPairableTimeout = 0\nAlwaysPairable = true" \
       /etc/bluetooth/main.conf
grep -q '^\[Policy\]' /etc/bluetooth/main.conf || echo '[Policy]' >> /etc/bluetooth/main.conf
sed -i '/^\[Policy\]/a AutoEnable = true' /etc/bluetooth/main.conf

echo "==> PIN file / PIN dosyası"
install -d -m 755 /etc/piwoofer
echo "* $PIN" > /etc/piwoofer/pins
chmod 600 /etc/piwoofer/pins

echo "==> Persistent pairing store / Kalıcı eşleşme deposu"
# The root filesystem becomes read-only (overlay). Pairings live in a small ext4 image on the
# boot partition, loop-mounted on /var/lib/bluetooth by a systemd mount unit (NOT fstab: overlayroot
# would remount fstab entries read-only).
# Kök dosya sistemi salt okunur olacağı için eşleşmeler boot bölümündeki küçük bir ext4 imajında
# tutulur (fstab DEĞİL, systemd mount unit: overlayroot fstab girdilerini salt okunur yapar).
IMG=/boot/firmware/btstate.img
systemctl stop bluetooth 2>/dev/null || true
umount /var/lib/bluetooth 2>/dev/null || true
if [ ! -f "$IMG" ]; then
  dd if=/dev/zero of="$IMG" bs=1M count="$BT_IMG_MB" status=none
  mkfs.ext4 -q -L btstate "$IMG"
fi
sed -i '/btstate.img/d' /etc/fstab
cat > /etc/systemd/system/var-lib-bluetooth.mount <<EOF
[Unit]
Description=Persistent Bluetooth pairing store
After=boot-firmware.mount
Requires=boot-firmware.mount
[Mount]
What=$IMG
Where=/var/lib/bluetooth
Type=ext4
Options=loop,noatime
[Install]
WantedBy=bluetooth.service
EOF

echo "==> systemd units"
mkdir -p /etc/systemd/system/bluetooth.service.d
cat > /etc/systemd/system/bluetooth.service.d/piwoofer.conf <<EOF
[Unit]
RequiresMountsFor=/var/lib/bluetooth
[Service]
ExecStartPre=/usr/sbin/rfkill unblock bluetooth
EOF

# Legacy PIN pairing: turn Secure Simple Pairing off, otherwise phones pair without asking for a PIN.
# Eski tip PIN eşleşmesi: SSP kapatılır, yoksa telefonlar PIN sormadan eşleşir.
cat > /usr/local/bin/piwoofer-bt-setup <<'EOF'
#!/bin/bash
for i in $(seq 1 30); do bluetoothctl list 2>/dev/null | grep -q Controller && break; sleep 1; done
# btmgmt needs a live stdin pipe (it hangs / prints nothing on /dev/null or a tty)
sleep 2 | timeout 10 btmgmt -i hci0 power off >/dev/null || true
sleep 2 | timeout 10 btmgmt -i hci0 ssp off   >/dev/null || true
sleep 2 | timeout 10 btmgmt -i hci0 bredr on  >/dev/null || true
sleep 2 | timeout 10 btmgmt -i hci0 power on  >/dev/null || true
bluetoothctl power on
bluetoothctl pairable on
bluetoothctl discoverable on
# Power-cycling the adapter resets the device class to one WITHOUT the Audio bit (0x440414), which
# makes phones hide the device in their scan list. Restore "Audio / Loudspeaker".
# Adaptörü kapatıp açmak sınıfı Audio biti olmayan değere (0x440414) çevirir, telefonlar cihazı
# listede göstermez. "Audio / Loudspeaker" sınıfını geri yazıyoruz.
hciconfig hci0 class 0x240414 || true
hciconfig hci0 name "__NAME__" || true
exit 0
EOF
sed -i "s/__NAME__/$NAME/" /usr/local/bin/piwoofer-bt-setup
chmod +x /usr/local/bin/piwoofer-bt-setup

cat > /etc/systemd/system/piwoofer-bt.service <<EOF
[Unit]
Description=Piwoofer Bluetooth setup (PIN pairing, discoverable)
After=bluetooth.service bluealsa.service
Requires=bluetooth.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/piwoofer-bt-setup
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/piwoofer-agent.service <<EOF
[Unit]
Description=Piwoofer Bluetooth pairing agent (PIN)
After=piwoofer-bt.service
Requires=bluetooth.service
[Service]
ExecStart=/usr/bin/bt-agent -c NoInputNoOutput -p /etc/piwoofer/pins
Restart=always
KillSignal=SIGINT
TimeoutStopSec=5
[Install]
WantedBy=multi-user.target
EOF

# BlueALSA: A2DP sink only; the player sends every connected source to the ALSA card
mkdir -p /etc/systemd/system/bluealsa.service.d /etc/systemd/system/bluealsa-aplay.service.d
cat > /etc/systemd/system/bluealsa.service.d/piwoofer.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/bluealsa -S -p a2dp-sink --keep-alive=5
EOF
cat > /etc/systemd/system/bluealsa-aplay.service.d/piwoofer.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/bluealsa-aplay -S --pcm=plughw:CARD=$ALSA_CARD,DEV=0 --pcm-buffer-time=$BUFFER_US --pcm-period-time=$PERIOD_US --profile-a2dp 00:00:00:00:00:00
Restart=always
RestartSec=2
EOF

cat > /etc/systemd/system/piwoofer-volume.service <<EOF
[Unit]
Description=Set analog output volume
After=sound.target
[Service]
Type=oneshot
ExecStart=/usr/bin/amixer -c 0 sset PCM $VOLUME
[Install]
WantedBy=multi-user.target
EOF

echo "==> Watchdog + volatile logs / Watchdog + RAM'de loglar"
mkdir -p /etc/systemd/system.conf.d /etc/systemd/journald.conf.d
printf '[Manager]\nRuntimeWatchdogSec=15\nRebootWatchdogSec=2min\n' > /etc/systemd/system.conf.d/watchdog.conf
printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=20M\n' > /etc/systemd/journald.conf.d/volatile.conf

if [ "$DISABLE_WIFI" = "1" ]; then
  echo "==> Disabling Wi-Fi / Wi-Fi kapatılıyor"
  grep -q '^dtoverlay=disable-wifi' /boot/firmware/config.txt || \
    printf '\n[all]\ndtoverlay=disable-wifi\n' >> /boot/firmware/config.txt
fi

echo "==> Enabling services / Servisler açılıyor"
systemctl daemon-reload
systemctl enable var-lib-bluetooth.mount bluetooth bluealsa bluealsa-aplay \
                 piwoofer-bt piwoofer-agent piwoofer-volume
systemctl restart bluetooth bluealsa piwoofer-bt piwoofer-agent bluealsa-aplay piwoofer-volume
sleep 3
systemctl --no-pager --failed || true
bluetoothctl show | grep -E 'Name:|Powered|Discoverable:|Pairable:' || true
echo
echo "Done. Pair a device with name '$NAME' and PIN '$PIN'."
echo "Bitti. '$NAME' cihazını PIN '$PIN' ile eşleştir."
echo "Then run / Sonra çalıştır: scripts/enable-readonly.sh"
