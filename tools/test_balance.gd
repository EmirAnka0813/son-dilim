extends SceneTree
##
## DENGE MEKANİĞİ DOĞRULAMA TESTİ (headless)
## ============================================================================
## Çalıştırma:
##   godot --headless --script res://tools/test_balance.gd
##
## Test edilenler:
##   1. SARKAÇ: serbest bırakıldığında yerçekimiyle düze döner
##   2. SÜRDÜRME: sabit ivme kutuya açısal ivme verir
##   3. KREM KAYMASI: eşik aşılınca slip artar
##   4. İYİLEŞME: kutu düzeltilince slip azalır
##   5. DÜŞÜRME: slip 1.0'a ulaşınca sinyal yayınlanır
##   6. ÇOCUK DOSTU: durup düzeltmek yeterli (oynanabilirlik)
##   7. SINIR: açı ±PI'yi geçmez
## ============================================================================

var passed: int = 0
var failed: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("  PASS  ", label, (" -> " + detail) if detail != "" else "")
	else:
		failed += 1
		print("  FAIL  ", label, (" -> " + detail) if detail != "" else "")


func _init() -> void:
	print("\n=== SON DİLİM — DENGE MEKANİĞİ DOĞRULAMA ===\n")

	_test_swing_returns_to_center()
	_test_constant_acceleration()
	_test_slip_accumulates()
	_test_slip_recovers()
	_test_drop_signal()
	_test_playable_recovery()
	_test_angle_clamp()
	_test_math_consistency()

	print("\n=== SONUÇ: %d/%d geçti ===\n" % [passed, passed + failed])
	quit(0 if failed == 0 else 1)


func _make_balance() -> CakeBalance:
	var b := CakeBalance.new()
	## Sahne ağacına eklemeden de çalışabilmesi için process'i kapatıp
	## manuel adımlıyoruz.
	b.set_physics_process(false)
	return b


func _step(b: CakeBalance, seconds: float, dt: float = 1.0 / 60.0) -> void:
	var steps: int = int(seconds / dt)
	for i in steps:
		b._step_swing(dt)
		b._step_slip(dt)


## 1. Serbest bırakılan kutu yerçekimiyle düze dönmeli.
func _test_swing_returns_to_center() -> void:
	var b := _make_balance()
	b.set_angle(0.9)
	_step(b, 3.0)
	_check("Sarkaç yerçekimiyle düze döner",
		absf(b.angle) < 0.15,
		"9 saniye sonra açı = %.3f rad" % b.angle)


## 2. Sabit ivme kutuya etki etmeli (sert fren kremi öne kaçırmalı).
func _test_constant_acceleration() -> void:
	var b := _make_balance()
	## +X yönünde sürekli ivme (oyuncu hızlanıyor).
	for i in 60:
		b.apply_acceleration(Vector3(8.0, 0.0, 0.0))
		b._step_swing(1.0 / 60.0)
	var right: float = b.angle
	_check("İvme kutuya açısal ivme verir", absf(right) > 0.05,
		"sağa ivmede açı = %.4f rad" % right)

	## Ters yönde ivme → ters açı.
	var b2 := _make_balance()
	for i in 60:
		b2.apply_acceleration(Vector3(-8.0, 0.0, 0.0))
		b2._step_swing(1.0 / 60.0)
	_check("Ters ivme ters yönde eğer", b2.angle < 0.0,
		"sola ivmede açı = %.4f rad" % b2.angle)


## 3. Eşik aşılınca krem kaymalı.
##    NOT: set_angle() sadece ANLIK açı verir; sarkaç hemen yerçekimiyle
##    düzleşir ve eşiğin altına düşer. Bu yüzden gerçek bir EĞİM kaynağı
##    kullanıyoruz: sürekli ivme (sert fren) kutu eğik tutar.
func _test_slip_accumulates() -> void:
	var b := _make_balance()
	for i in 300:
		## Sürekli ivme → kutu eğik kalır → krem kayar.
		b.apply_acceleration(Vector3(11.0, 0.0, 0.0))
		b._step_swing(1.0 / 60.0)
		b._step_slip(1.0 / 60.0)
	_check("Eşik aşılınca krem kayar", b.slip > 0.05,
		"slip = %.4f, açı = %.3f" % [b.slip, b.angle])


## 4. Kutu düzeltilince krem geri oturmalı.
func _test_slip_recovers() -> void:
	var b := _make_balance()
	## 1) Sert frenle eğilmiş kutu → krem kayar.
	for i in 180:
		b.apply_acceleration(Vector3(11.0, 0.0, 0.0))
		b._step_swing(1.0 / 60.0)
		b._step_slip(1.0 / 60.0)
	var peak: float = b.slip
	## 2) Oyuncu durur ve kutuyu düzeltir (Q ile sola).
	##
	## NOT: Oyun artık `set_manual_input()` DEĞİL `add_correction()`
	## kullanıyor (çift etki düzeltmesi). Test de oyunla aynı yolu
	## kullanmalı — aksi halde test, oyunda olmayan bir mekaniği ölçer.
	b.apply_acceleration(Vector3.ZERO)
	for i in 240:
		## Q basılı: sola düzeltme (kutu sağa eğikse).
		b.add_correction(-1.0, 2.2 * (1.0 / 60.0) * 60.0)
		b._step_swing(1.0 / 60.0)
		b._step_slip(1.0 / 60.0)
	_check("Düzeltilince krem geri oturur", b.slip < peak,
		"%.4f -> %.4f" % [peak, b.slip])


## 5. Slip 1.0'a ulaşınca düşme sinyali yayınlanmalı.
func _test_drop_signal() -> void:
	var b := _make_balance()
	## Sinyal + b.dropdown bayrağı kontrol edilir.
	## NOT: GDScript lambda'ları YEREL değişkenleri değil, üyeleri değere
	## göre yakalar — lambda içindeki "dropped = true" dışarıya YAZMAZ.
	## Bu yüzden b.dropped (üye) okunur.
	var signal_fired: Array[bool] = [false]
	b.cake_dropped.connect(func() -> void: signal_fired[0] = true)
	for i in 900:
		b.apply_acceleration(Vector3(14.0, 0.0, 0.0))
		b._step_swing(1.0 / 60.0)
		b._step_slip(1.0 / 60.0)
		if b.dropped:
			break
	_check("Slip 1.0'da pasta düşer",
		b.dropped and signal_fired[0] and b.slip >= b.slip_limit,
		"slip = %.3f, sinyal=%s" % [b.slip, str(signal_fired[0])])


## 6. OYNANABİLİRLİK: durup düzeltmek kaza yapmamalı.
##    Bu, 9 yaşındaki oyuncu için kritik kural.
func _test_playable_recovery() -> void:
	var b := _make_balance()
	## Oyuncu koşarken kutu eğilmiş, sonra DURUP düzeltiyor.
	b.set_angle(0.9)
	b.set_manual_input(-1.0)
	_step(b, 1.0)
	var mid: float = b.slip
	## Düzeltmeyi bırakıyor (eller serbest), kutu ortalamaya dönmeli.
	b.clear_manual_input()
	_step(b, 4.0)
	_check("Durup bırakınca kurtarılabilir",
		b.slip < 0.05 and not b.dropped,
		"slip: %.4f -> %.4f, düştü=%s" % [mid, b.slip, str(b.dropped)])


## 7. Açı ±PI sınırını geçmemeli.
func _test_angle_clamp() -> void:
	var b := _make_balance()
	b.set_angle(3.0)
	b.angular_velocity = 40.0
	_step(b, 2.0)
	_check("Açı ±PI sınırında kalır", absf(b.angle) <= PI + 0.001,
		"açı = %.4f" % b.angle)


## 8. Tutarlılık: normalize edilmiş değerler doğru aralıkta mı?
func _test_math_consistency() -> void:
	var b := _make_balance()
	b.set_angle(b.max_manual_tilt)
	var ratio: float = b.get_tilt_ratio()
	_check("Tilt ratio -1..1 aralığında", ratio >= -1.0 and ratio <= 1.0,
		"tilt ratio = %.3f" % ratio)

	b.set_angle(0.0)
	b.slip = 0.5
	var slip_ratio: float = b.get_slip_ratio()
	_check("Slip ratio 0..1 aralığında", slip_ratio >= 0.0 and slip_ratio <= 1.0,
		"slip ratio = %.3f" % slip_ratio)

	## Fiziksel tutarlılık: daha büyük ivme → daha büyük açısal tepki.
	var gentle := _make_balance()
	var harsh := _make_balance()
	## Tek karelik ivme ETKISI: sarkac denge noktasina gitmeden olculecek
	## yon (erken tepki). Bu, ivme buyuklugune duyarli.
	gentle.apply_acceleration(Vector3(3.0, 0.0, 0.0))
	harsh.apply_acceleration(Vector3(12.0, 0.0, 0.0))
	gentle._step_swing(1.0 / 60.0)
	harsh._step_swing(1.0 / 60.0)
	var gentle_early: float = absf(gentle.angular_velocity)
	var harsh_early: float = absf(harsh.angular_velocity)
	_check("Daha sert ivme daha çok sarsar", harsh_early > gentle_early,
		"yumuşak=%.4f sert=%.4f (erken tepki)" % [gentle_early, harsh_early])

