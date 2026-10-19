# hype-bodycam — Exports

Kaynak adı `hype-bodycam` olmak zorunda (script başka bir isimle açılırsa kendini kapatır),
bu yüzden tüm çağrılar `exports["hype-bodycam"]` üzerinden yapılır.

| Export | Taraf | Ne işe yarar |
| --- | --- | --- |
| [`bodycam`](#bodycam) | client | ox_inventory item kullanımı, elle çağrılmaz |
| [`IsBodycamOn`](#isbodycamon) | client | Oyuncunun kendi yaka kamerası kayıtta mı |
| [`Open`](#open) | client | İzleme listesini açar |
| [`Close`](#close) | client | İzlemeyi / listeyi kapatır |
| [`IsOpen`](#isopen) | client | İzleme arayüzü açık mı |
| [`GetViewingStream`](#getviewingstream) | client | O an izlenen yayının id'si |
| [`IsBodycamActive`](#isbodycamactive) | server | Bir oyuncunun kamerası kayıtta mı |
| [`SetBodycam`](#setbodycam) | server | Bir oyuncunun kamerasını aç / kapat |
| [`GetStreams`](#getstreams) | server | Aktif tüm yayınların listesi |
| [`GetViewers`](#getviewers) | server | Bir yayını izleyen oyuncular |

---

## Client

### bodycam

```lua
exports("bodycam", function(item, slot) end)
```

ox_inventory'nin item kullanımı için çağırdığı export; `data/items.lua` içinde
`client.export = "hype-bodycam.bodycam"` olarak tanımlanır. Item kullanıldığında sunucuya
aç/kapat isteği gönderir. **Kendi scriptinden elle çağırma**, kamerayı kod ile açmak için
sunucu tarafındaki [`SetBodycam`](#setbodycam) kullanılır.

Diğer envanterlerde (qb-inventory, ESX envanteri vb.) item kullanımı bu export'tan değil,
sunucu tarafında framework üzerinden kaydedilen usable item'dan geçer; iki yol da aynı
aç/kapat fonksiyonuna düşer.

| Parametre | Tip | Açıklama |
| --- | --- | --- |
| `item` | `table` | ox_inventory item verisi, kullanılmıyor |
| `slot` | `table?` | Item'ın kullanıldığı slot, seri numarası bu slottan okunur |

Dönüş: yok.

---

### IsBodycamOn

```lua
local recording = exports["hype-bodycam"]:IsBodycamOn()
```

Oyuncunun kendi yaka kamerasının o an kayıt yapıp yapmadığını söyler. Durum sunucudan gelir,
yani client tarafında sahte bir değer tutulmaz. Örneğin bir HUD scriptinde "kayıtta" ikonu
göstermek veya kamera açıkken belli bir işlemi engellemek için kullanılır.

Dönüş: `boolean` — kayıt sürüyorsa `true`.

---

### Open

```lua
exports["hype-bodycam"]:Open()
```

Yayın izleme listesini açar. Terminale bağlı değildir: bu şekilde açıldığında oyuncu
terminalden uzaklaşsa bile izleme kapanmaz, o yüzden kendi menünden (tablet, telefon, MDT)
açmak için uygundur. Açılmadan önce sunucuda yetki kontrolü yapılır; yetki yoksa oyuncuya
hata bildirimi gider ve liste açılmaz.

Dönüş: yok.

---

### Close

```lua
exports["hype-bodycam"]:Close()
```

Açık olan izlemeyi ve listeyi kapatır: kamerayı yok eder, HUD ve radarı geri getirir,
oyuncunun donmuş pozisyonunu serbest bırakır ve sunucudaki izleyici kaydını siler.
Oyuncuyu kameradan zorla çıkarman gereken durumlarda (ölüm, kelepçe, cutscene, başka bir
menünün açılması) çağır.

Dönüş: yok.

---

### IsOpen

```lua
local open = exports["hype-bodycam"]:IsOpen()
```

İzleme arayüzünün açık olup olmadığını söyler; hem yayın listesi hem de canlı izleme ekranı
"açık" sayılır. Kendi menülerini açmadan önce çakışmayı önlemek için kullanılır.

Dönüş: `boolean` — liste veya bir yayın ekranda ise `true`.

---

### GetViewingStream

```lua
local id = exports["hype-bodycam"]:GetViewingStream()
```

O an izlenen yayının id'sini verir. Id biçimi: yaka kameraları `b<server id>`
(örn. `b14`), araç kameraları `d<netId>` (örn. `d2188`). Sadece liste açıkken veya hiçbir şey
izlenmiyorken `nil` döner.

Dönüş: `string?` — yayın id'si, izlenmiyorsa `nil`.

---

## Server

### IsBodycamActive

```lua
local recording = exports["hype-bodycam"]:IsBodycamActive(source)
```

Belirtilen oyuncunun yaka kamerasının kayıtta olup olmadığını söyler. Sunucu tarafındaki
gerçek kayıt durumudur; log, ceza, soruşturma veya "kamerası kapalıyken şunu yapamaz" gibi
kontroller için güvenle kullanılabilir.

| Parametre | Tip | Açıklama |
| --- | --- | --- |
| `source` | `number` | Oyuncunun server id'si |

Dönüş: `boolean` — kayıt sürüyorsa `true`.

---

### SetBodycam

```lua
local ok = exports["hype-bodycam"]:SetBodycam(source, true)
```

Bir oyuncunun yaka kamerasını kod ile açar veya kapatır. Açarken normal kurallar uygulanır:
oyuncunun üzerinde bodycam item'ı olmalı ve yetkili bir meslekte (gerekiyorsa mesaide)
olmalı; bu şartlar sağlanmazsa veya kamera zaten açıksa `false` döner ve hiçbir şey değişmez.
Kapatma her zaman çalışır ve `"export"` sebebiyle loglanır. Kamera açılırken normal başlangıç
bipi çalar ve araçtaysa araç kamerası da devreye girer.

| Parametre | Tip | Açıklama |
| --- | --- | --- |
| `source` | `number` | Oyuncunun server id'si |
| `active` | `boolean` | `true` = kaydı başlat, `false` = kaydı durdur |

Dönüş: `boolean` — işlem yapıldıysa `true`, açma reddedildiyse `false`.

---

### GetStreams

```lua
local streams = exports["hype-bodycam"]:GetStreams()
```

Aktif tüm yayınları id'ye göre anahtarlanmış bir tablo olarak verir. Kaç kamera açık,
kim kayıtta, hangi araç kayıt alıyor gibi bilgileri tek seferde almak için kullanılır
(örn. yönetici paneli, canlı istatistik, Discord bildirimi).

> Dönen tablo scriptin kendi tablosudur, **kopya değildir**. Sadece okumak için kullan,
> içeriğini değiştirme.

Her yayın şu alanları taşır:

| Alan | Tip | Açıklama |
| --- | --- | --- |
| `id` | `string` | Yayın id'si (`b<server id>` veya `d<netId>`) |
| `type` | `"body"` \| `"dash"` | Yaka kamerası mı, araç kamerası mı |
| `owner` | `number` | Yaka: memurun server id'si, araç: araçtaki (son) memur |
| `name` | `string` | Karakter adı |
| `callsign` | `string?` | Çağrı kodu, yoksa `nil` |
| `job` | `string?` | Meslek etiketi (örn. "Police") |
| `grade` | `string?` | Rütbe adı, sadece yaka kamerasında |
| `serial` | `string` | Cihaz seri numarası (X + 8 hane) |
| `trigger` | `string` | Kaydı başlatan olay: `manual`, `sidearm`, `vehicle`, `entry`, `lights` |
| `startedAt` | `number` | Kaydın başladığı an (`os.time`) |
| `netId` | `number?` | Aracın network id'si, sadece araç kamerasında |
| `plate` | `string?` | Araç plakası, sadece araç kamerasında |
| `model` | `number?` | Araç model hash'i, sadece araç kamerasında |
| `lights` | `boolean?` | Çakar açık mı, sadece araç kamerasında |

---

### GetViewers

```lua
local all = exports["hype-bodycam"]:GetViewers()
local watchers = exports["hype-bodycam"]:GetViewers("b14")
```

Yayın izleyen oyuncuların server id'lerini verir. Id verilirse sadece o yayını izleyenler,
id verilmezse herhangi bir yayını izleyen tüm oyuncular döner. "Bu memuru kimler izliyor"
veya "şu an kaç kişi terminalde" gibi bilgiler için kullanılır.

| Parametre | Tip | Açıklama |
| --- | --- | --- |
| `id` | `string?` | Yayın id'si; `nil` verilirse tüm izleyiciler |

Dönüş: `number[]` — oyuncu server id'leri listesi.

---

## Ek: olaylar ve state

Export olmayan ama dışarıdan kullanılabilen iki olay ve bir state bag var.

```lua
-- Sunucu tarafı: bir yayın başladığında / bittiğinde tetiklenir (log scriptleri için)
AddEventHandler("hype-bodycam:server:streamStarted", function(stream) end)
AddEventHandler("hype-bodycam:server:streamStopped", function(stream, reason) end)
```

`stream` tablosu [`GetStreams`](#getstreams) bölümündeki alanları taşır. `reason` kaydın
neden kapandığını söyler: `off` (elle kapatıldı), `invalid` (item/mesai kaybı),
`dropped` (oyuncu çıktı), `export` ([`SetBodycam`](#setbodycam) ile), `vehicle` (araç yok
veya hurda), `lights` (araçta kameralı memur kalmadı ve çakar kapalı), `owner_*`
(yayın sahibinin kamerası kapandı).

```lua
-- Her iki taraf: aktif yayınların canlı listesi
local streams = GlobalState["hype-bodycam:streams"]
```

Sunucu yayın listesini bu global state bag üzerinden dağıtır, yani client tarafında da aynı
listeyi okuyabilirsin. Yapısı [`GetStreams`](#getstreams) ile aynıdır ve sadece okunur.
