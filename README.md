# SON DİLİM — The Last Slice

**Büyük abi, 10 yaşına giren kardeşi Derin'in doğum günü pastasını, şehirde
pasta kutusuyla koşarak eve götürür.**

---

## 🎮 OYNA

```
C:\Users\Lenovo\OneDrive\Masaüstü\SON-DILIM\SON-DILIM.exe
```

Windows build · 93 MB · çift tıkla çalışır.

Linux build: `release/linux64/SON-DILIM.x86_64`

### Akış

1. **SMS bildirimi** gelir (2 sn)
2. **Mesajlar otomatik akar** (her 2.6 sn) — hiçbir şeye tıklamana gerek yok
3. **"BAŞLA →" butonu** belirir (~8 sn) — ekran ortasında, altın renkli
4. Butona bas → **oyun başlar**

### Kamera

Üçüncü şahıs **yörünge kamerası**. Kamera, `Player` node'unun **altında
değil** — `Main` düzeyinde ayrı bir `CameraPivot` olarak durur. Böylece:

- Karakter döner → **kamera yerinde kalır**
- `W` her zaman **kameranın baktığı yöne** götürür
- Karakter **yürüdüğü yöne bakar** (Roblox/TPS standardı)

`res/scripts/camera_pivot.gd` · `elevation = -pitch` yörünge matematiği.

---

## ⌨️ KONTROLLER

| Tuş | İşlev |
|---|---|
| `W` `A` `S` `D` | Kamera yönüne göre hareket |
| **SAĞ FARE basılı + sürükle** | Kamerayı döndürür (yatay + pitch) |
| `Q` / `E` | Pasta kutusunu sola / sağa düzeltir |
| `SPACE` / SOL FARE | Zıplar |
| `SHIFT` | Hızlı koşar |
| `V` | Birinci şahıs kameraya geçer |
| `ESC` | Duraklatır |

**Prologue**: SMS bildirimi gelir → ekrana dokun → mesajlar → `BAŞLA`

---

## 🗺️ BÖLÜMLER

| # | Bölüm | Uzunluk | Mekanik |
|---|---|---|---|
| 1 | **Ofisten Kaçış** | 60 m | Masa engelleri, asansör boşluğu (zıpla) |
| 2 | **Trafik Canavarı** | 90 m | Akan araçlar, yayalar, köpekler, **ıslak zemin** |
| 3 | **Toplu Taşıma Kabusu** | 80 m | 26 kişilik kalabalık, tren tüneli, dar geçitler |
| 4 | **Son Yokuş** | 78 m | Yükselen rampa, kaykaycılar, eve varış |

**Toplam: 4 bölüm, 308 m, 20 dk (kronometre 20:00)**

---

## 🎯 OYUN MEKANİKLERİ

### A. Pasta Denge Mekaniği

Kutu omuzda taşınırken krem kayar. Fizik bir **sarkaç** modelidir:

```
θ'' = -(g/L)·sin(θ) − c·θ' + k·(a/a_ref)²·projeksiyon(θ)
```

| Sembol | Değer | Anlamı |
|---|---|---|
| `θ` / `θ'` | — | eğim açısı / açısal hız |
| `g` | 9.8 m/s² | yerçekimi |
| `L` | 1.15 m | sarkaç boyu |
| `c` | 3.6 | sönüm katsayısı |
| `a_ref` | 8 m/s² | referans ivme |

**Krem kayması**: `slip += (|θ| − 0.62) · 0.55 /sn` → `slip = 1.0` → **PASTA DÜŞTÜ!**
**İyileşme**: `slip −= 0.30 /sn` (kutu düzeltilince, `Q`/`E` ile)

**İvme etkisi KARESEL ölçeklenir**: `(a/a_ref)²`. Doğrusal olsaydı sarkaç denge
noktasında kilitlenir ve "sert fren" hissedilmezdi. Ölçülen fark: hafif fren
`0.0105` vs sert fren `0.1687` — **16× fark**.

### B. Zaman Baskısı

Sağ üstte geri sayan kronometre. Süre azaldıkça **müzik temposu hızlanır**
(`pitch_scale` artar). Süre biterse → komik final.

### C. Engeller

Akan trafik · yayalar · sokak köpekleri · inşaat konileri · ıslak zemin
(kayma katsayısı ×1.6) · kalabalık (basınç) · tren vagonları · kaykaycılar

Hiçbir çarpışma **can** götürmez — sadece kutuyu sarsar.

---

## 🏗️ TEKNİK

| | |
|---|---|
| **Motor** | Godot Engine 4.4-stable (GDScript) |
| **Render** | Vulkan Forward+ / RTX 3060 |
| **3D Modelleme** | Blender 4.2.3 LTS — 13 low-poly GLB (692 KB) |
| **Doku** | Prosedürel tileable value-noise → 6 PNG (albedo + normal) |
| **Ses** | Python sentez (BFXR tarzı) → 10 WAV |
| **Font** | Press Start 2P (SIL OFL) |
| **Export** | Windows x86_64 + Linux x86_64 |

### Klasör yapısı

```
res/
  scenes/   Main · Player · Level_Office · Level_Street · Level_Metro
            Level_Hill · UI · FinalScreen · Prologue
  scripts/  player_controller.gd · balance_system.gd · game_manager.gd
            ui_controller.gd · level_kit.gd · level_lighting.gd
            level_*.gd · final_screen.gd · prologue.gd · main.gd
  assets/   models/ (13 GLB) · textures/ (6 PNG) · audio/ (10 WAV)
            photos/ (4 JPG)
  fonts/    ArcadeFont.ttf
  shaders/  wet_asphalt.gdshader
tools/      build_assets.py · make_textures.py · capture.gd
            test_balance.gd · test_flow.gd · test_perf.gd · test_playable.gd
```

### Öne çıkan teknikler

**`wet_asphalt.gdshader`** — Su mikro boşlukları doldurur → pürüzlülük
`0.88 → 0.06`, normal detayı düzleşir, yağmur ripple'ı + Fresnel kenar
yansıması. Oyuncu ıslak bölgeye girince `wetness` yumuşak geçişle artar.

**`level_lighting.gd`** — Ortak ışık stratejisi. Soğuk ay ışığı + sıcak
yapay ışıklar + soğuk ambient = sinematik sıcak/soğuk bölünme. AgX tonemap.

**`level_kit.gd`** — Modüler çevre kiti: metre sabitleri, 1 m ızgara, tek
giriş noktası (`add_box` / `add_sloped_box` / `add_cylinder` / `add_light`).

**MultiMesh** — Tekrarlayan yol çizgileri 13 ayrı mesh → 1 çizim çağrısı.

---

## 🧪 DOĞRULAMA — 63/63 TEST GEÇİYOR

| Suite | Test | Sonuç |
|---|---|---|
| `test_balance.gd` | Denge fiziği (sarkaç, kayma, ivme ölçekleme) | **11/11** |
| `test_flow.gd` | Oyun akışı (4 bölüm, checkpoint, kronometre, sonlar) | **30/30** |
| `test_perf.gd` | Karmaşıklık (draw call, üçgen, ışık, nesne) | **13/13** |
| `test_start_flow.gd` | **Başlatma akışı** (buton görünür, tıklanır, oyun başlar) | **20/20** |
| `test_playable.gd` | **Oynanabilirlik — bot 4 bölümü de bitiriyor** | **9/9** |
| `test_character.gd` | Karakter ayakta, yüz doğru yönde, pasta elde | **7/7** |
| `test_game_logic.gd` | **Oyun mantığı** (denge, Q/E, karakter yönü, yokuş) | **20/20** |
| `test_camera_3d.gd` | **3B kamera** (yükseklik, look_at, pitch, takip) | **10/10** |
| `--check-only` | 14 script parse kontrolü | **0 hata** |
| Export | Windows + Linux build + çalıştırma | **hatasız** |

**TOPLAM: 120/120**

### Bot testi (`test_playable.gd`)

Bot gerçek fizik döngüsünde oynuyor: hedefe yürüyor, denge bozulunca
`Q`/`E` ile düzeltiyor, engele takılınca zıplıyor, pasta düşünce checkpoint'e
dönüyor. **4 bölümün 4'ünü de tamamlıyor.**

### Performans

| Bölüm | Mesh | Üçgen | Işık |
|---|---|---|---|
| Ofis | 91 | ~1.1k | 3 |
| Sokak | 827 | ~11.7k | 25 |
| Metro | 250 | ~3.4k | 1 |
| Yokuş | 161 | ~2.1k | 19 |

Hepsi 500k üçgen sınırının çok altında.

---

## 🔁 YENİDEN ÜRETİM

**Asset'leri yeniden üret:**
```bash
blender --background --python tools/build_assets.py
python tools/make_textures.py
```

**Testleri çalıştır:**
```bash
godot --headless --script res://tools/test_balance.gd
godot --headless --script res://tools/test_flow.gd
godot --headless --script res://tools/test_perf.gd
godot --headless --script res://tools/test_playable.gd
```

**Görüntü al:**
```bash
godot --resolution 1280x720 --path . --script res://tools/capture.gd -- res://shots
```

**Build:**
```bash
godot --headless --export-release "Windows Desktop" build/windows/SON-DILIM.exe
godot --headless --export-release "Linux" build/linux/SON-DILIM.x86_64
```

---

## 💡 HİKÂYE DETAYI

**"İYİ Kİ DOĞDUN DERİN!"**

- **Ekranda**: Altın gradient başlık + konfeti + aile fotoğraf şeridi
  (DERİN / Abla / Anne / Baba) + Derin'in konuşma balonu:
  *"Abi, pastayı getirdin mi? Ben burada bekliyordum!"*
- **Dünyada**: Bölüm 4'te evin kapısının üstünde **neon tabela** olarak yazar.
- **Komik finalde**: *"Bari pastanın üzerine bir mum dikelim, böyle de yeriz!"*
- **Süre biterse**: *"Abi? Pastayı getirdin mi? Telefonu açtım, sesin gidiyor..."*

---

## 📜 LİSANS

Oyun kodu ve asset'ler bu repo için özgün.
Press Start 2P fontu SIL Open Font License ile dağıtılmaktadır.
Godot Engine MIT, Blender GPL (ikisi de sıfır maliyetli ve açık kaynak).
