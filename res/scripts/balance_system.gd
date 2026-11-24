extends Node
class_name CakeBalance
##
## PASTA DENGE MEKANİĞİ (The Cake Balance System)
## ============================================================================
## Kutu omuzda taşınırken krem kayabilir. Oyuncu Q/E ile kutuyu eğitir,
## koşu/ziplama/çarpma ise kutuya sarsıntı verir.
##
## ── MATEMATİK ───────────────────────────────────────────────────────────────
## Kutu, 2 boyutlu bir sarkaç (pendulum) olarak modellenir:
##
##     θ'' = -(g/L)·sin(θ) - c·θ' + (a_x·cos(θ) + a_z·sin(θ))·k
##
##   θ     : kutunun eğim açısı (radyan). 0 = düz, + = sağa eğik.
##   θ'    : açısal hız (rad/sn) — sarkaç momentumu.
##   g     : yerçekimi ivmesi (9.8 m/s²) — kremi aşağı çeker.
##   L     : sarkaç boyu (m). Küçük L = hızlı salınım.
##   c     : sönüm katsayısı (1/sn). Yüksek c = çabuk durur.
##   a_x,a_z: oyuncunun yatay ivmesi (m/s²). Kutu bu ivmeye karşı tepki verir:
##            sert fren → krem öne kaçar, viraj → krem yana kaçar.
##   k     : ivme → açısal ivme çarpanı (1/m).
##
## "Krem kayması" (slip) ayrı bir birikim değişkenidir:
##
##     d(slip)/dt = max(0, |θ| - θ_safe) · leak_rate
##
##   |θ| ≤ θ_safe  → krem yerinde, kayma yok.
##   |θ| > θ_safe  → krem yavaşça dışarı taşar (accumulation).
##   slip ≥ 1.0    → PASTA DÜŞTÜ.
##
## Oyuncu tepki verdiğinde slip AZALIR (krem geri yerine oturur):
##
##     d(slip)/dt = -recovery_rate   (kutu düzeltildikçe)
##
## Böylece mekanik "dur ve düzelt" ile oynanabilir — 9 yaş için adil.
##
## ── ÇOCUK DOSTU AYARLAR ───────────────────────────────────────────────────
##   θ_safe = 0.62 rad (~35°)  → krem kaymaya başlama eşiği
##   leak   = 0.55 /sn          → krem kaçış hızı
##   recover= 0.30 /sn          → düzeltirken krem geri gelir
##   Yarıçap: herhangi bir çarpışmada can gitmez, sadece kutu sarsılır.
## ============================================================================

## ── DENGE PARAMETRELERİ (tunable) ───────────────────────────────────────────
@export_group("Sarkaç")
## Kutunun etkin sarkaç boyu (m). Küçük değer = hızlı, keskin salınım.
@export var pendulum_length: float = 1.15
## Sönüm katsayısı (1/sn). Yüksek = çabuk durur, oynanabilir.
@export var damping: float = 3.6
## Yerçekimi ivmesi (m/s²). 9.8 = gerçekçi.
@export var gravity: float = 9.8
## İvme → açısal ivme çarpanı (1/m). Sert frenin etkisini belirler.
## 0.075 → 0.095: kutu ivmeye daha duyarlı, yürüyüş bile zorlar.
@export var accel_gain: float = 0.095
## Referans ivme (m/s²) — bu büyüklükteki ivme tam etki üretir.
## Karesel ölçeklemenin ölçeği: "ne kadar sert fren" algısı.
@export var accel_reference: float = 8.0

@export_group("Krem Kayması")
## Krem kaymaya başladığı eşik açı (radyan).
##
## ZORLUK NOTU: 0.62 → 0.42. Ölçülen hata: "sadece yürüyerek oyun
## bitirilebiliyordu". 0.62 rad eşiği, oyuncunun normal koşu ivmesiyle
## (a ≈ 3-5 m/s²) ürettiği açıyı (≈ 0.3 rad) aşmadığı için denge
## mekaniği hiç devreye girmiyordu. 0.42 rad ile orta hızda koşmak
## bile kremi kaydırır → oyuncu Q/E'ye basmak ZORUNLU olur.
@export var slip_threshold: float = 0.42
## Eşik aşılınca kremin dışarı taşma hızı (birim/sn).
## 0.55 → 0.70 (krem daha hızlı akar, oyuncu tepki vermek zorunda).
@export var slip_leak_rate: float = 0.70
## Kutu düzeltildikçe kremin geri oturma hızı (birim/sn).
@export var slip_recovery_rate: float = 0.30
## Bu değere ulaşınca pasta düşer.
@export var slip_limit: float = 1.0

@export_group("Girdi")
## Q/E tuşlarının verdiği hedef eğim açısı (radyan).
@export var max_manual_tilt: float = 0.75
## Oyuncunun elle verdiği düzeltmenin sertliği (1/sn²).
@export var tilt_response: float = 14.0

signal balance_changed(angle: float, slip: float)
signal cake_dropped()
signal slip_warning()

## ── DURUM ───────────────────────────────────────────────────────────────────
## Kutunun mevcut eğim açısı (radyan). Pozitif = sağa eğik.
var angle: float = 0.0
## Açısal hız (rad/sn).
var angular_velocity: float = 0.0
## Krem kayma miktarı. 0 = yerinde, 1 = düştü.
var slip: float = 0.0
## Kutu düşmüş mü?
var dropped: bool = false
## Son karede uygulanan ivme (m/s²) — debug için.
var last_accel: Vector2 = Vector2.ZERO

## Girdi hedefi: Q/E'den gelen manuel düzeltme.
var _manual_target: float = 0.0
## Uyarı sesi bir kez çalması için.
var _warned: bool = false
## Son kare ölçümü.
var _time: float = 0.0
## Oyuncu şu anda kutu düzeltiyor mu? (Q/E basılı)
var _correcting: bool = false
## Düzeltme yönü kutunun eğikliğiyle uyumlu mu? (1.0 = tam uyum, 0.35 = yanlış yön)
var _correction_aligned: float = 1.0


func _ready() -> void:
	## Sahne ağacında tek başına da çalışabilsin diye zamanı elle yönetiyoruz.
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if dropped:
		return
	_time += delta
	var prev_angle: float = angle

	_step_swing(delta)
	_step_slip(delta)

	if absf(angle) > absf(prev_angle) or absf(slip) > 0.001:
		balance_changed.emit(angle, slip)


## ═══════════════════════════════════════════════════════════════════════════
## SARKAÇ ADIMI
## ═══════════════════════════════════════════════════════════════════════════
## Sapmış yay özellikle çocuklar için hafifletilmiştir:
##   · Küçük açılarda (|θ| < 0.35 rad) doğrusal yaklaşım kullanılır → sarkaç
##     "yumuşak" hissettirir, titreşmez.
##   · Büyük açılarda sinüsel terim devreye girer → kutu aşırı savrulmaz.
##
## _physics_process(delta) içinde `angle` ve `angular_velocity` güncellenir.
func _step_swing(delta: float) -> void:
	## 1) Oyuncunun düzeltme girdisi (Q/E) → hedef açı.
	##    Hedef açı doğrudan uygulanmaz; sarkaç hedefe doğru çekilir.
	var restoring: float = 0.0
	if absf(_manual_target) > 0.001:
		## Hedefe doğru güçlü çekim — oyuncunun elleri kutuya etki ediyor.
		restoring = (_manual_target - angle) * tilt_response

	## 2) Yerçekimi: krem aşağı çeker → kutuyu düz tutmaya çalışır.
	var gravity_term: float = -(gravity / pendulum_length) * sin(angle)
	if absf(angle) < 0.35:
		## Doğrusal yaklaşım: sin(θ) ≈ θ (hafif açılarda daha yumuşak).
		gravity_term = -(gravity / pendulum_length) * angle

	## 3) Sönüm: hareketi yavaşlatır.
	var damping_term: float = -damping * angular_velocity

	## 4) İvme tepkisi: oyuncunun yatay ivmesi kutuyu sarsar.
	##    a_x → kutu öne/arkana savrulur, a_z → yana savrulur.
	##    Kutu açısıyla çarpılır: eğim dikse ivme etkisi zayıflar.
	##
	##    ÖNEMLİ: ivme büyüklüğü DOĞRUSAL değil, KARESEL olarak ölçeklenir.
	##    Doğrusal ölçeklemede sarkaç denge noktasına oturur ve "sert fren"
	##    "hafif fren"den HİSSEDİLMEZ. Karesel ölçekleme farkı oyuncuya
	##    taşır: sert fren kutuya çok daha çok vurur.
	##
	##        accel_term = k · (a / a_ref)² · projeksiyon(θ)
	##
	##    a_ref = 8 m/s² referans ivme — bu büyüklükte tam etki.
	var accel_term: float = 0.0
	var accel_mag: float = last_accel.length()
	if accel_mag > 0.01:
		## Yön: ivme hangi yanda? Kutunun açısına göre projeksiyon.
		var accel_dir: Vector2 = last_accel / accel_mag
		## θ=0 (kutu düz): X ivmesi tam etki, Z ivmesi sıfır.
		## θ=π/2 (kutu yan): X sıfır, Z tam etki.
		var projection: float = accel_dir.x * cos(angle) + accel_dir.y * sin(angle)
		## Büyüklük: karesel ölçekleme.
		var normalized: float = accel_mag / accel_reference
		var magnitude_factor: float = normalized * normalized
		accel_term = projection * magnitude_factor * accel_gain * 60.0

	## 5) Toplam açısal ivme ve entegrasyon (yarım ölçüm — symplectic Euler).
	var angular_accel: float = gravity_term + damping_term + restoring + accel_term
	angular_velocity += angular_accel * delta
	angle += angular_velocity * delta

	## 6) Sınır: kutu 180°'yi geçemez (fiziksel olarak imkânsız).
	if angle > PI:
		angle = PI
		angular_velocity = -angular_velocity * 0.3
	elif angle < -PI:
		angle = -PI
		angular_velocity = -angular_velocity * 0.3


## ═══════════════════════════════════════════════════════════════════════════
## KREM KAYMASI ADIMI
## ═══════════════════════════════════════════════════════════════════════════
func _step_slip(delta: float) -> void:
	var overflow: float = maxf(0.0, absf(angle) - slip_threshold)

	if overflow > 0.0:
		## Krem dışarı taşıyor. Taşma miktarı eşiği aştıkça artar.
		## DÜZELTME AKTİFSE taşma YAVAŞLAR (oyuncunun elleri kremi tutuyor).
		var leak: float = slip_leak_rate * delta
		if _correcting:
			leak *= (1.0 - 0.75 * _correction_aligned)
		slip += overflow * leak
		if slip >= slip_limit:
			slip = slip_limit
			dropped = true
			dropped_signal_emit()
	else:
		## Kutu güvenli bölgede → krem yavaşça geri oturur.
		## DÜZELTME AKTİFSE geri oturma HIZLANIR (oyuncu kremi geri koyar).
		var recovery: float = slip_recovery_rate * delta
		if _correcting:
			recovery *= (1.0 + 1.6 * _correction_aligned)
		slip = maxf(0.0, slip - recovery)

	## Uyarı: krem kaymaya başladığında bir kez haber ver.
	if slip > 0.35 and not _warned:
		_warned = true
		slip_warning.emit()
	elif slip < 0.15:
		_warned = false


## ── OYUNCU DÜZELTMESİ (Q/E) ────────────────────────────────────────────────
## Oyuncunun kutu eğimini düzeltme eylemi.
##
## TASARIM: Düzeltme kutu açısını HIZLA değiştirmez; kutunun ağırlık merkezini
## hedefe doğru kaydırır. Fiziksel olarak doğru — insan kutuyu düzeltirken
## kaldırmaz, eğimini yavaşça düzeltir. Krem bu yüzden geri oturur.
##
##   direction: -1 = sola, +1 = sağa
##   strength : uygulama gücü (0..1 aralığı hedef açıya çevrilir)
func add_correction(direction: float, strength: float = 2.2) -> void:
	if direction == 0.0:
		return
	##
	## DÜZELTME ETKİSİ GERÇEK OLMALI.
	##
	## ÖLÇÜLEN HATA ("sadece yürüyerek bitirilebiliyor"): Eski
	## implementasyonda düzeltme sadece `_manual_target` hedef açısını
	## kaydırıyordu. Hedef açı `max_manual_tilt` (0.75 rad) ile
	## sınırlıydı ve `slip_threshold` (0.62) üstünde olduğu için
	## oyuncu kutu "düzeltirken" bile krem akmaya devam ediyordu.
	## Sonuç: oyuncu Q/E'ye hiç basmadan da bölümleri bitirebiliyordu.
	##
	## DOĞRU TASARIM: Düzeltme yapılırken:
	##   1) hedef açı kutu açısına ÇEKİLİR (kutu düzelir),
	##   2) krem kayması doğrudan AZALIR (oyuncunun elleri kremi geri
	##      yerine oturtur).
	##
	## Bu, "dur ve düzelt" hissini güçlendirir: oyuncu Q/E'ye basmazsa
	## krem kaymaya devam eder, basarsa krem geri gelir.
	##
	## DÜZELTME GÜCÜ:
	## strength oyunda `2.2 * delta * 60.0` olarak gelir (~2.2/kare).
	## Eski ölçek (0.012) bunu ~0.026'ya çeviriyordu — çok yavaş.
	## Ölçülen sonuç: kutu 1.54 rad'a eğildi, oyuncu 5 saniyede
	## düzeltemedi, krem 0.90'da takılı kaldı.
	##
	## Yeni ölçek: delta ≈ 0.10/kare → saniyede ~6 rad hedef kayması,
	## yani 0.5 saniyede kutu tamamen düzelir. Hissedilir ama kontrollü.
	var delta: float = direction * clampf(strength * 0.045, 0.02, 0.16)
	## Hedef açıyı kaydır (mevcut davranış) + sınırsız kısmı koru.
	_manual_target = clampf(_manual_target + delta, -max_manual_tilt, max_manual_tilt)
	## ── KRİTİK: Aktif düzeltme sırasında krem GERİ otursun ──
	##
	## DİKKAT: `_step_slip()` zaten "kutu güvenli bölgedeyse" kremi
	## geri oturtur. Burada EK azaltma yapmak çift azaltma olurdu
	## (ölçülen hata: test 0.8965 → 0.9583, yani slip ARTMIŞTI).
	##
	## Doğrusu: kutu EŞİĞİN ÜSTÜNDEyken bile düzeltme kremi geri
	## oturtmalı. Bunu `_step_slip` içinde, "düzeltme aktif" bayrağıyla
	## yapıyoruz — burada sadece bayrağı yönetiyoruz.
	##
	## Düzeltme yönü, kutunun eğikliğine TERS olmalı:
	## kutu sağa eğikse (+angle) oyuncu SOLA basar (-direction).
	var against_tilt: float = -signf(angle) if absf(angle) > 0.02 else 0.0
	var aligned: float = 1.0 if (against_tilt == 0.0 or signf(direction) == against_tilt) else 0.35
	_correcting = aligned > 0.9
	_correction_aligned = aligned
	## Kutuyu düzelt: hedef açıyı kutuya doğru çek.
	## Eğer kutunun açısı zaten küçükse hedefi SIFIRLA (kutu düzeldi).
	if absf(angle) < 0.05:
		_manual_target = 0.0
	else:
		_manual_target = lerpf(_manual_target, 0.0, clampf(absf(delta) * 6.0, 0.0, 1.0))


## ── DIŞ API ─────────────────────────────────────────────────────────────────
## Oyuncunun ivmesi (m/s²) — dünya uzayında X/Z. Sarsıntıyı bu üretir.
func apply_acceleration(accel: Vector3) -> void:
	last_accel = Vector2(accel.x, accel.z)


## Oyuncu Q/E ile kutuyu eğitir. -1 = sola, +1 = sağa.
func set_manual_input(axis: float) -> void:
	_manual_target = clampf(axis, -1.0, 1.0) * max_manual_tilt


## Manuel girdi bırakılınca kutu ortalamaya dönmek ister.
func clear_manual_input() -> void:
	_manual_target = 0.0


## Belirli bir açıya anında ulaş (teleport / reset).
func set_angle(new_angle: float) -> void:
	angle = new_angle
	angular_velocity = 0.0


## Tam sıfırlama — yeni bölüm başlangıcı veya checkpoint dönüşü.
func reset() -> void:
	angle = 0.0
	angular_velocity = 0.0
	slip = 0.0
	dropped = false
	_warned = false
	_manual_target = 0.0
	last_accel = Vector2.ZERO
	_correcting = false
	_correction_aligned = 1.0


## Anlık çarpışma sarsıntısı (dolu bardak çarpması, tabela çarpması).
## impulse: açısal hıza eklenecek değer (rad/sn).
func add_impulse(impulse: float) -> void:
	angular_velocity += impulse


## Krem kayması oranı (0..1) — UI için.
func get_slip_ratio() -> float:
	return clampf(slip / slip_limit, 0.0, 1.0)


## Eğim açısı normalize (-1..1) — UI çubuğu için.
func get_tilt_ratio() -> float:
	return clampf(angle / max_manual_tilt, -1.0, 1.0)


## Kutu düştü mü diye sinyal yayınla (ayrı fonksiyon: test edilebilirlik için).
func dropped_signal_emit() -> void:
	cake_dropped.emit()
