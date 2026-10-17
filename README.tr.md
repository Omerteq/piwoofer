# Piwoofer

[English](README.md) | **Türkçe**

Bir Raspberry Pi 4'ü ve kablolu herhangi bir ses sistemini **tak-çalıştır Bluetooth hoparlöre** çevirir.
Fişe tak, telefonunu ya da laptopunu bir kere eşleştir, gerisi kendiliğinden çalışır. Fişi çekmek güvenlidir.

## Özellikler

- Normal bir Bluetooth hoparlör (A2DP alıcı) olarak `Piwoofer` adıyla görünür.
- **PIN ile eşleşme** (eski tip eşleşme, PIN ayarlanabilir). Her zaman görünür ve eşleşmeye açık.
- Eşleşmiş cihazlar otomatik bağlanır. Birden çok cihaz eşleşebilir, hangisi çalarsa o duyulur.
- **Ani kapanmaya dayanıklı:** Kök dosya sistemi salt okunur RAM overlay olarak çalışır, fişi çekmek SD kartı bozmaz. Eşleşmeler ayrı küçük bir imajda tutulduğu için kalıcıdır.
- Donma olursa donanım watchdog'u Pi'yi yeniden başlatır. Servisler kendiliğinden yeniden başlar.
- Düşük gecikmeli çalma tamponu (ayarlanabilir).
- İsteğe bağlı: Wi-Fi kapalı, sadece Ethernet. Bluetooth etkilenmez.

## Gereksinimler

- Raspberry Pi 4 (Bluetooth çipi dahili). Dahili Bluetooth'u olan diğer modeller de çalışmalı.
- Raspberry Pi OS Lite, 64-bit, Debian 13 "Trixie" (test edildi). Bookworm'da da çalışması beklenir ama test edilmedi.
- 3.5 mm jack'e bağlı ses sistemi (varsayılan) ya da herhangi bir ALSA kartı (USB DAC, DAC HAT).
- Pi'ye SSH erişimi ve `sudo` yetkili bir kullanıcı.

## Nasıl çalışır

| Parça | Görevi |
| --- | --- |
| `bluez` | Bluetooth yığını |
| `bluez-alsa` (`bluealsa`, `bluealsa-aplay`) | A2DP sesini alır ve ALSA'ya çalar. Sistem servisleridir, masaüstü oturumu ya da PipeWire gerekmez. |
| `bt-agent` (bluez-tools) | PIN ile cevap veren eşleşme ajanı |
| `btmgmt ssp off` | Secure Simple Pairing'i kapatır. Kapatılmazsa modern telefonlar PIN sormadan eşleşir. |
| `overlayroot` (`raspi-config` ile) | RAM overlay'li salt okunur kök dizin |
| `btstate.img` | Boot bölümünde 16 MB'lık ext4 imajı. systemd mount unit ile `/var/lib/bluetooth` üzerine bağlanır, böylece eşleşmeler reboot'tan sonra kalır. |
| systemd watchdog | Donmada donanımsal reset |

## Kurulum

1. Raspberry Pi OS Lite (64-bit) yaz, SSH'ı aç, Ethernet ile bağla ve SSH ile gir.
2. Bu repoyu Pi'ye kopyala ve kurulum betiğini çalıştır:

   ```bash
   git clone https://github.com/Omerteq/piwoofer.git
   cd piwoofer
   sudo PIN=1234 NAME=Piwoofer DISABLE_WIFI=1 ./scripts/install.sh
   ```

3. Telefonunu/laptopunu PIN ile `Piwoofer`'a eşleştir ve sesi dene.
4. Ani kapanmaya karşı güvenli hale getir ve reboot at:

   ```bash
   sudo ./scripts/enable-readonly.sh
   sudo reboot
   ```

5. Gerekirse tekrar eşleş, Pi'nin fişini çekip tak ve otomatik bağlandığını doğrula.

### Kurulum seçenekleri (ortam değişkenleri)

| Değişken | Varsayılan | Anlamı |
| --- | --- | --- |
| `PIN` | `0000` | Eşleşme PIN'i. **Değiştir.** |
| `NAME` | `Piwoofer` | Bluetooth cihaz adı |
| `ALSA_CARD` | `Headphones` | `aplay -l` çıktısındaki çıkış kartı (3.5 mm jack = `Headphones`). USB DAC: denenmedi, [aşağıya bak](#diğer-ses-kartları-usb-dac---denenmedi) |
| `VOLUME` | `90%` | Açılıştaki analog çıkış seviyesi (telefondaki ses bunun üstüne çalışır) |
| `BUFFER_US` | `100000` | Çalma tamponu (mikrosaniye). Düşük = az gecikme, cızırtı riski. |
| `PERIOD_US` | `25000` | Çalma periyodu (mikrosaniye) |
| `DISABLE_WIFI` | `0` | `1` ise `dtoverlay=disable-wifi` ekler (reboot gerekir) |

## Sonradan ayar değiştirme

Kök dizin salt okunur olduğu için, overlay'i kapatmazsan yaptığın değişiklikler reboot'ta silinir:

```bash
sudo ./scripts/disable-readonly.sh && sudo reboot
# ...değişikliği yap, örn. install.sh'i yeni PIN ile tekrar çalıştır...
sudo ./scripts/enable-readonly.sh && sudo reboot
```

Sadece sesi geçici (reboot'a kadar) değiştirmek için `amixer -c 0 sset PCM 80%` kullan.

## Kullanım

- PIN ile bir kere eşleş, sonra herhangi bir telefon/laptopun Bluetooth menüsünden bağlan.
- PIN'i ya da SSP ayarını değiştirirsen **her cihazda `Piwoofer`'ı unut** ve baştan eşleş. Yoksa cihazlar eski anahtarı kullanır ve PIN sormaz.

## Gecikme

Bluetooth A2DP (SBC kodeği) her zaman yaklaşık 100-200 ms gecikme ekler. Çoğu video oynatıcı bunu otomatik telafi eder. Piwoofer kendi tamponunu BlueALSA varsayılanı olan 500 ms'den 100 ms'ye düşürür. Videoda hâlâ gecikme varsa `BUFFER_US` değerini düşür (örneğin `60000`) ya da 3.5 mm jack yerine USB DAC dene (denenmedi, aşağıya bak).

## Diğer ses kartları (USB DAC) - denenmedi

Piwoofer sadece Raspberry Pi'nin **3.5 mm jack**'iyle yapıldı ve test edildi. USB DAC ya da DAC HAT gibi diğer ALSA ses kartları teoride çalışmalı, ama henüz kimse denemedi.

**Elle denemek**

```bash
aplay -l                                   # kart adını bul, örn. "card 1: Device [USB Audio Device]" -> Device
sudo ALSA_CARD=Device PIN=1234 ./scripts/install.sh
```

**Açılıştaki ses ayarı başka kartlarda neden hata verebilir**

Ses seviyesi doğrudan ses çipinde, bir "mixer kontrolü" ile ayarlanır ve her çip kontrollerine farklı isim verir. Pi'nin jack'i `PCM` adında tek bir kontrol sunar, kurulum da `amixer -c 0 sset PCM 90%` komutunu çalıştırır. Bir USB DAC'te bu kontrol `Speaker`, `Headphone`, `Master` ya da `Digital` adında olabilir, hiç donanım ses kontrolü olmayabilir ve kart numarası 0 olmayabilir.

Kartında `PCM` yoksa `piwoofer-volume` servisi açılışta hata verir. **Ses yine çalar**, çünkü bu adım sadece başlangıç seviyesini ayarlar; telefondaki ses çubuğu BlueALSA'nın yazılım ses kontrolünü kullanır ve buna bağlı değildir. Kartının hangi kontrolleri sunduğunu görmek için: `amixer -c <kart numarası> scontrols`.

**Katkılar memnuniyetle karşılanır**

USB DAC'in ya da başka bir ses kartın varsa yardım edebilirsin:

- **Bildir:** `aplay -l` çıktını, `amixer -c <n> scontrols` çıktını, DAC'in hangisi olduğunu ve sesin çalışıp çalışmadığını yazarak bir issue aç.
- **Düzelt:** `scripts/install.sh` içindeki `piwoofer-volume` adımını, sabit `-c 0 ... PCM` yerine seçilen `ALSA_CARD` kartını kullanacak ve kontrol yoksa sessizce geçecek şekilde düzelten bir pull request gönder.
- **Sonra:** Birkaç kartın çalıştığı doğrulanınca otomatik kart algılama eklenebilir.

Git'i iyi bilmen gerekmez: çıktılarınla açılmış bir issue bile büyük yardımdır. Kod değişikliği için repoyu fork'la, bir branch aç ve pull request gönder.

## Sorun giderme

| Belirti | Çözüm |
| --- | --- |
| Telefon PIN sormadan eşleşiyor | SSP hâlâ açık. `sudo btmgmt -i hci0 info` çıktısında `ssp` olmamalı. Telefonda cihazı unut ve baştan eşleş. |
| `btmgmt` takılıyor ya da hiçbir şey yazmıyor | Canlı bir stdin borusu ister. `sleep 2 \| sudo btmgmt -i hci0 info` kullan. |
| Pi görünmüyor | `rfkill list`, sonra `sudo rfkill unblock bluetooth`; `bluetoothctl show` kontrol et. |
| Bağlı ama ses yok | `aplay -l` ile kart adını kontrol et, `ALSA_CARD`'ı ayarla, `systemctl status bluealsa-aplay` bak. |
| Reboot sonrası eşleşmeler gitti | Overlay gizliyor. `mount \| grep bluetooth` çıktısında `btstate.img`'nin `/var/lib/bluetooth` üzerine rw bağlı olduğunu kontrol et. |
| Hoparlörde cızırtı | `BUFFER_US`'u artır, amfi kırpıyorsa `VOLUME`'u düşür. |

Faydalı komutlar:

```bash
systemctl status bluetooth bluealsa bluealsa-aplay piwoofer-bt piwoofer-agent
journalctl -u piwoofer-agent -u bluealsa-aplay -b
bluetoothctl devices
```

## Güvenlik

PIN ile eşleşme rahatlık için bir engeldir, güçlü güvenlik değildir: eski tip 4 haneli PIN, menzildeki biri tarafından denenerek bulunabilir. Cihaz her zaman eşleşmeye açıktır. Bu önemliyse `AlwaysPairable` ve `discoverable on` ayarlarını kapat, sadece gerektiğinde eşleş.

## Kaldırma

Overlay'i kapat (yukarıya bak), sonra:

```bash
sudo systemctl disable --now piwoofer-bt piwoofer-agent piwoofer-volume bluealsa-aplay bluealsa var-lib-bluetooth.mount
sudo rm -f /etc/systemd/system/piwoofer-*.service /etc/systemd/system/var-lib-bluetooth.mount \
           /usr/local/bin/piwoofer-bt-setup /boot/firmware/btstate.img
sudo rm -rf /etc/systemd/system/{bluetooth,bluealsa,bluealsa-aplay}.service.d /etc/piwoofer
```

## Lisans

MIT - [LICENSE](LICENSE) dosyasına bak.
