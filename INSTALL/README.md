# hype-bodycam — Kurulum

Axon tarzı yaka kamerası ve araç kamerası sistemi. Script qbx_core, qb-core ve
es_extended üzerinde çalışır; framework, envanter, target ve bildirim sistemini
kendisi tespit eder.

## 1. Gereksinimler

| Tür | Desteklenen | Not |
| --- | --- | --- |
| Zorunlu | `ox_lib` | Tek zorunlu bağımlılık |
| Framework | `qbx_core`, `qb-core`, `es_extended` | Biri yeterli, otomatik seçilir |
| Envanter | `ox_inventory`, `qb-inventory`, `ps-inventory` (+ HasItem için codem / core / jpr / origen / tgiann) | Yoksa framework envanterine düşer |
| Target | `ox_target`, `qb-target` | Yoksa terminaller oluşmaz, sadece komut/export ile açılır |
| Bildirim | `ox_lib`, `okokNotify`, `ps-ui` | `Config.Notifications` ile seçilir |

Seri numarasının item'a yazılabilmesi için `ox_inventory` veya `qb-inventory`
gerekir. Diğer kurulumlarda seri karakter kimliğinden türetilir (aşağıya bak).

## 2. Klasör adı

Klasör adı **`hype-bodycam`** olmalı. Başka bir isimle açılırsa script kendini
kapatır ve konsola uyarı yazar. Tüm export'lar da bu isim üzerinden çağrılır.

## 3. Dosyaları yerleştir

1. Klasörü `resources` içine kopyala (örn. `resources/[numberone]/hype-bodycam`).
2. `server.cfg` içine ekle — sıra önemli, bu satır `ox_lib`, framework, envanter ve
   target'tan **sonra** gelmeli:

```cfg
ensure ox_lib
ensure qbx_core          # veya qb-core / es_extended
ensure ox_inventory      # veya qb-inventory
ensure ox_target         # veya qb-target
ensure hype-bodycam
```

## 4. Item'ı ekle

Kullandığın envantere göre **sadece birini** uygula. Item adı `Config.Item` ile
aynı olmalı (varsayılan: `bodycam`).

### ox_inventory

`INSTALL/ox-inventory.lua` içeriğini `ox_inventory/data/items.lua` içine ekle.
Item kullanımı `client.export = "hype-bodycam.bodycam"` ile bu scripte düşer.

Görsel: `INSTALL/item-images/bodycam.png` → `ox_inventory/web/images/bodycam.png`

### qb-inventory / ps-inventory

`INSTALL/qb-inventory.lua` içeriğini `qb-core/shared/items.lua` içine ekle.
Item kullanımı framework'ün usable item sistemine kaydedilir, ek bir tanım gerekmez.

Görsel: `INSTALL/item-images/bodycam.png` → `qb-inventory/html/images/bodycam.png`

### es_extended (envanter resource'u yoksa)

`INSTALL/esx.sql` dosyasını veritabanında çalıştır. ESX'te item veritabanında
tutulur. Dosyanın içinde eski ESX (`limit` kolonlu) için alternatif insert de var.

Görsel: envanter resource'una göre değişir, örn.
`esx_inventoryhud/html/img/items/bodycam.png`

## 5. Config

`config/config.lua` içinde en az şunlara bak:

| Ayar | Ne yapman gerekiyor |
| --- | --- |
| `Item` | Envantere eklediğin item adıyla aynı olmalı |
| `Access.groups` | Kamerayı açabilecek meslekler: `{ police = 0 }` → meslek adı ve minimum rütbe seviyesi |
| `ViewAccess.groups` | Yayınları izleyebilecek meslekler |
| `ViewAccess.ace` | Bu ace'e sahip olanlar meslek aranmadan izler, kapatmak için `false` |
| `Access.requireDuty` | Mesai zorunluluğu (ESX'te mesai sistemi olmadığı için yoksayılır) |
| `Terminals` | İzleme terminallerinin koordinatları, kendi karakolların için güncelle |
| `Notifications` | `"auto"` veya `okokNotify` / `ps-ui` / `ox_lib` |
| `Command` | İzleme listesini açan komut, `false` = sadece terminal |
| `Debug` | Kurulumu test ederken `true`, canlıda `false` |

Dil seçimi `server.cfg` üzerinden yapılır (`locales/en.json`, `locales/tr.json`):

```cfg
setr ox:locale "tr"
```

## 6. Test

1. Sunucuyu başlat, konsolda hata olmadığını kontrol et.
2. `Debug = true` ile başlat; konsolda `framework bridge: ...` ve
   `inventory module bound to ...` satırlarını gör.
3. Yetkili bir mesleğe gir ve mesaiye başla.
4. Item'ı ver (`/giveitem` veya envanter menüsü) ve kullan → ekranda Axon göstergesi
   çıkmalı, başlangıç bipi duyulmalı.
5. Dashcam'li bir araca (varsayılan: Emergency sınıfı) bin → ikinci bir yayın açılmalı.
6. Terminale git (varsayılan: Mission Row PD bilgisayarı) ve yayını izle.
7. Her şey çalışıyorsa `Debug = false` yap.

## 7. Sorun giderme

| Konsoldaki mesaj / belirti | Sebep ve çözüm |
| --- | --- |
| `No supported framework found` | qbx_core / qb-core / es_extended çalışmıyor ya da hype-bodycam onlardan önce başlıyor, `ensure` sırasını düzelt |
| `no supported inventory found, falling back to the framework inventory` | Envanter resource'u yok veya sonra başlıyor; ESX'in kendi envanteriyle bu normal |
| `no supported target resource found, bodycam terminals were not created` | ox_target / qb-target yok, terminaller oluşmadı; `Config.Command` ile komut tanımlayabilirsin |
| `this inventory cannot store metadata, using the character serial` | Envanter item metadata tutmuyor (ESX envanteri); seri karakter başına sabit olur, item başına ayrı seri için ox_inventory kullan |
| Item kullanılıyor ama hiçbir şey olmuyor | Item adı `Config.Item` ile aynı mı, ox_inventory'de `client.export` satırı eklendi mi, qb/ESX'te item `useable` mı |
| "You must be on duty" bildirimi | Meslek `Access.groups` içinde değil, rütbe seviyesi düşük ya da mesaide değilsin |
| Terminalde "No access" | `ViewAccess.groups` veya `ViewAccess.ace` ayarını kontrol et |
| Yayın açılıyor ama görüntü "NO SIGNAL" | Hedef oyuncu/araç çok uzakta yüklenmiyor olabilir, `CullingPadding` değerini artır |

Debug açıkken script akışın her adımını (yetki kontrolleri, kamera bağlama, yayın
başlangıç/bitiş, izleyiciler) konsola yazar; sorun ararken ilk oraya bak.

## 8. Arayüzü değiştireceksen

Arayüz `web/build` içinde derlenmiş olarak geliyor, normal kurulumda bir şey
yapmana gerek yok. Kaynağı düzenlersen `web/` klasöründe:

```bash
pnpm install
pnpm build
```

## 9. Diğer scriptlerle entegrasyon

Export'lar ve olaylar için `exports.md` dosyasına bak: kamera durumunu okuma,
kod ile açıp kapatma, aktif yayın listesi, izleyiciler ve log için
`hype-bodycam:server:streamStarted` / `streamStopped` olayları.
