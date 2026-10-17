# Piwoofer

**English** | [Türkçe](README.tr.md)

Turn a Raspberry Pi 4 and any wired speaker system into a **plug-and-play Bluetooth speaker**.
Plug it in, pair your phone or laptop once, and it just works. Pulling the plug is safe.

## Features

- Appears as a normal Bluetooth speaker (A2DP sink) named `Piwoofer`.
- **PIN pairing** (legacy pairing, configurable PIN). Always discoverable and pairable.
- Paired devices reconnect automatically. Several devices can be paired; whichever plays gets heard.
- **Survives power loss:** root filesystem runs as a read-only RAM overlay, so SD card corruption from yanking the plug is avoided. Pairings are stored in a separate small image so they persist.
- Hardware watchdog restarts the Pi if it freezes. Services restart themselves.
- Low-latency playback buffer (tunable).
- Optional: Wi-Fi disabled, Ethernet only. Bluetooth keeps working.

## Requirements

- Raspberry Pi 4 (the Bluetooth chip is built in). Other models with onboard Bluetooth should also work.
- Raspberry Pi OS Lite, 64-bit, Debian 13 "Trixie" (tested). Bookworm should work but is untested.
- Speaker system connected to the 3.5 mm jack (default), or any ALSA card (USB DAC, DAC HAT).
- SSH access to the Pi and a user with `sudo`.

## How it works

| Part | Role |
| --- | --- |
| `bluez` | Bluetooth stack |
| `bluez-alsa` (`bluealsa`, `bluealsa-aplay`) | Receives A2DP audio and plays it to ALSA. System services, no desktop session or PipeWire needed. |
| `bt-agent` (bluez-tools) | Pairing agent that answers with the PIN |
| `btmgmt ssp off` | Disables Secure Simple Pairing. Without this, modern phones pair without asking for a PIN. |
| `overlayroot` (via `raspi-config`) | Read-only root with a RAM overlay |
| `btstate.img` | 16 MB ext4 image on the boot partition, loop-mounted on `/var/lib/bluetooth` by a systemd mount unit, so pairings survive reboots |
| systemd watchdog | Hardware reset on freeze |

## Install

1. Flash Raspberry Pi OS Lite (64-bit), enable SSH, connect via Ethernet, and SSH in.
2. Copy this repo to the Pi and run the installer:

   ```bash
   git clone https://github.com/Omerteq/piwoofer.git
   cd piwoofer
   sudo PIN=1234 NAME=Piwoofer DISABLE_WIFI=1 ./scripts/install.sh
   ```

3. Pair your phone/laptop with `Piwoofer` using your PIN and test playback.
4. Make it power-loss safe, then reboot:

   ```bash
   sudo ./scripts/enable-readonly.sh
   sudo reboot
   ```

5. Pair again if needed, unplug and re-plug the Pi to confirm it reconnects automatically.

### Installer options (environment variables)

| Variable | Default | Meaning |
| --- | --- | --- |
| `PIN` | `0000` | Pairing PIN. **Change it.** |
| `NAME` | `Piwoofer` | Bluetooth device name |
| `ALSA_CARD` | `Headphones` | Output card from `aplay -l` (3.5 mm jack = `Headphones`). USB DAC: untested, see [below](#other-sound-cards-usb-dac---untested) |
| `VOLUME` | `90%` | Analog output level at boot (the phone controls volume on top of it) |
| `BUFFER_US` | `100000` | Playback buffer in microseconds. Lower = less latency, more risk of crackle. |
| `PERIOD_US` | `25000` | Playback period in microseconds |
| `DISABLE_WIFI` | `0` | `1` adds `dtoverlay=disable-wifi` (needs reboot) |

## Changing settings later

The root filesystem is read-only, so changes are lost on reboot unless you turn the overlay off first:

```bash
sudo ./scripts/disable-readonly.sh && sudo reboot
# ...make your changes, e.g. re-run install.sh with a new PIN...
sudo ./scripts/enable-readonly.sh && sudo reboot
```

To change only the volume or buffer temporarily (until reboot), use `amixer -c 0 sset PCM 80%` or edit nothing and just reboot to revert.

## Usage

- Pair once with the PIN, then connect from the Bluetooth menu of any phone/laptop.
- If you change the PIN or SSP setting, **forget `Piwoofer` on every device** and pair again, otherwise they reuse the old key and skip the PIN.

## Latency

Bluetooth A2DP (SBC codec) always adds roughly 100-200 ms. Most video players compensate automatically. Piwoofer reduces its own buffer from the BlueALSA default (500 ms) to 100 ms. If audio still lags in videos, lower `BUFFER_US` (for example `60000`), or try a USB DAC instead of the 3.5 mm jack (untested, see below).

## Other sound cards (USB DAC) - untested

Piwoofer was built and tested only with the Raspberry Pi's **3.5 mm jack**. Other ALSA sound cards, such as a USB DAC or a DAC HAT, should work in theory, but nobody has tried them yet.

**Trying it by hand**

```bash
aplay -l                                   # find your card name, e.g. "card 1: Device [USB Audio Device]" -> Device
sudo ALSA_CARD=Device PIN=1234 ./scripts/install.sh
```

**Why the boot volume step may fail on other cards**

Volume is set on the sound chip itself through a "mixer control", and every chip names its controls differently. The Pi's jack exposes one control called `PCM`, and the installer runs `amixer -c 0 sset PCM 90%`. A USB DAC may call it `Speaker`, `Headphone`, `Master` or `Digital`, may have no hardware volume at all, and may not be card number 0.

If `PCM` does not exist on your card, the `piwoofer-volume` service reports an error at boot. **Audio still plays**, because that step only sets the starting level; the volume slider on your phone uses BlueALSA's software volume and does not depend on it. To see what your card offers: `amixer -c <card number> scontrols`.

**Contributions welcome**

If you have a USB DAC or another sound card, you can help:

- **Report:** open an issue with your `aplay -l` output, the `amixer -c <n> scontrols` output, which DAC it is, and whether audio worked.
- **Fix:** send a pull request that makes the `piwoofer-volume` step in `scripts/install.sh` use the selected `ALSA_CARD` instead of a fixed `-c 0 ... PCM`, and skip quietly when the control does not exist.
- **Later:** once a few cards are confirmed, automatic card detection can be added.

You do not need to know Git well: an issue with your outputs is already a big help. For code changes, fork the repo, make a branch, and open a pull request.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Phone pairs but never asks for the PIN | SSP is still on. Check `sudo btmgmt -i hci0 info` - `ssp` must not appear in current settings. Forget the device on the phone and pair again. |
| `btmgmt` hangs or prints nothing | It needs a live stdin pipe. Use `sleep 2 \| sudo btmgmt -i hci0 info`. |
| Pi is not visible | `rfkill list`, then `sudo rfkill unblock bluetooth`; check `bluetoothctl show`. |
| Connected but silent | `aplay -l` to check the card name, set `ALSA_CARD`, check `systemctl status bluealsa-aplay`. |
| Pairings gone after reboot | Overlay hides them. Make sure `mount \| grep bluetooth` shows `btstate.img` mounted rw on `/var/lib/bluetooth`. |
| Crackle on the speaker | Raise `BUFFER_US`, or lower `VOLUME` if the amplifier clips. |

Useful commands:

```bash
systemctl status bluetooth bluealsa bluealsa-aplay piwoofer-bt piwoofer-agent
journalctl -u piwoofer-agent -u bluealsa-aplay -b
bluetoothctl devices
```

## Security

PIN pairing is a convenience barrier, not strong security: legacy 4-digit PINs can be brute-forced by someone in range. The device is always pairable. If that matters, disable `AlwaysPairable` and `discoverable on` and pair only when needed.

## Uninstall

Disable the overlay (see above), then:

```bash
sudo systemctl disable --now piwoofer-bt piwoofer-agent piwoofer-volume bluealsa-aplay bluealsa var-lib-bluetooth.mount
sudo rm -f /etc/systemd/system/piwoofer-*.service /etc/systemd/system/var-lib-bluetooth.mount \
           /usr/local/bin/piwoofer-bt-setup /boot/firmware/btstate.img
sudo rm -rf /etc/systemd/system/{bluetooth,bluealsa,bluealsa-aplay}.service.d /etc/piwoofer
```

## License

MIT - see [LICENSE](LICENSE).
