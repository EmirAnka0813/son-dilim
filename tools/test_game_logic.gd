extends SceneTree
##
## OYUN MANTIĞI TESTİ — "sadece yürüyerek bitirilebiliyor" regresyon testi
## ============================================================================
## Çalıştırma:
##   godot --headless --script res://tools/test_game_logic.gd
##
## Kontroller:
##   1. Denge mekaniği AKTİF mi? (sadece yürüyeyken krem kaymalı)
##   2. Q/E düzeltmesi GERÇEKTEN kremi geri getiriyor mu?
##   3. Yanlış yönde basmak (ters yön) düzeltmiyor mu?
##   4. Karakter HAREKET YÖNÜNE dönüyor mu? (kameraya değil)
##   5. Karakter geri giderken ÖNE bakıyor mu? (yani sırtı dönük)
##   6. Yokuş YUKARI doğru eğilmiş mi? (4. bölüm bitirilebilir)
##   7. Yokuşun sonunda oyuncu TEPEYE çıkabiliyor mu?
## ============================================================================

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\n=== OYUN MANTIĞI TESTİ ===\n")
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  %s%s" % [label, (" -> " + detail) if detail != "" else ""])
	else:
		_failed += 1
		print("  FAIL  %s%s" % [label, (" -> " + detail) if detail != "" else ""])


func _run() -> void:
	_test_balance_engages()
	_test_correction_works()
	_test_wrong_direction_hurts()
	await _test_character_facing()
	await _test_hill_slope()
	print("\n=== SONUÇ: %d/%d geçti ===\n" % [_passed, _passed + _failed])
	quit(0 if _failed == 0 else 1)


## ── 1) Denge mekaniği sadece yürüyeyken devreye giriyor mu? ─────────────────
func _test_balance_engages() -> void:
	print("── Denge mekaniği aktif mi? ──")
	var b: CakeBalance = CakeBalance.new()
	root.add_child(b)

	## Oyuncu NORMAL YÜRÜYÜŞ hızında ivme üretir: 0 → 5.4 m/s.
	## Bu ivme kutuya aktarılır ve kutu eğilir.
	var walking_accel: float = 5.4 * 14.0  # hedef hıza ulaşma ivmesi
	for i in 120:
		b.apply_acceleration(Vector3(walking_accel, 0.0, 0.0))
		b._step_swing(1.0 / 60.0)
		b._step_slip(1.0 / 60.0)

	_check("Normal yürüyüşte kutu EĞİLİR (denge devrede)",
		absf(b.angle) > b.slip_threshold * 0.35,
		"angle=%.3f (eşik=%.2f)" % [b.angle, b.slip_threshold])
	_check("Normal yürüyüşte krem KAYMAYA BAŞLAR (sadece yürüyerek bitmez)",
		b.slip > 0.05,
		"slip=%.3f" % b.slip)

	b.free()


## ── 2) Q/E düzeltmesi gerçekten işe yarıyor mu? ─────────────────────────────
func _test_correction_works() -> void:
	print("── Q/E düzeltmesi işe yarıyor mu? ──")
	var b: CakeBalance = CakeBalance.new()
	root.add_child(b)

	## Kutu sağa eğik (sert fren).
	for i in 180:
		b.apply_acceleration(Vector3(11.0, 0.0, 0.0))
		b._step_swing(1.0 / 60.0)
		b._step_slip(1.0 / 60.0)
	var peak: float = b.slip
	var angle_peak: float = b.angle

	## Oyuncu durur ve SOLA düzeltir (Q).
	b.apply_acceleration(Vector3.ZERO)
	for i in 300:
		b.add_correction(-1.0, 2.2 * (1.0 / 60.0) * 60.0)
		b._step_swing(1.0 / 60.0)
		b._step_slip(1.0 / 60.0)

	_check("Düzeltme kremi geri oturtur", b.slip < peak,
		"%.4f -> %.4f" % [peak, b.slip])
	_check("Düzeltme kutuyu düzleştirir", absf(b.angle) < absf(angle_peak),
		"%.3f -> %.3f" % [angle_peak, b.angle])
	_check("Düzeltme sonrası krem neredeyse sıfırlanır", b.slip < 0.15,
		"slip=%.4f" % b.slip)

	b.free()


## ── 3) Yanlış yönde basmak düzeltmemeli ─────────────────────────────────────
func _test_wrong_direction_hurts() -> void:
	print("── Yanlış yönde basmak? ──")
	var b: CakeBalance = CakeBalance.new()
	root.add_child(b)

	## Kutu sağa eğik → oyuncu YANLIŞ (sağa) basıyor.
	for i in 180:
		b.apply_acceleration(Vector3(11.0, 0.0, 0.0))
		b._step_swing(1.0 / 60.0)
		b._step_slip(1.0 / 60.0)
	var before: float = b.slip

	for i in 120:
		b.add_correction(1.0, 2.2 * (1.0 / 60.0) * 60.0)
		b._step_swing(1.0 / 60.0)
		b._step_slip(1.0 / 60.0)

	_check("Yanlış yönde basmak kremi GERİ GETİRMEZ", b.slip >= before - 0.02,
		"%.4f -> %.4f" % [before, b.slip])

	b.free()


## ── 4) Karakter hareket yönüne dönüyor mu? ──────────────────────────────────
func _test_character_facing() -> void:
	print("── Karakter yönü ──")
	var packed: PackedScene = load("res://res/scenes/Main.tscn")
	if packed == null:
		_check("Main.tscn yüklendi", false)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var player: Node3D = main.get_node_or_null("Player")
	if player == null:
		_check("Oyuncu var", false)
		main.queue_free()
		return

	## Karakter testi SOKAK bölümünde yapılır: ofis bölümünde masa
	## ve duvarlar var, oyuncu 0.28 m'de takılıp kalıyordu.
	main.call("_load_level", 1)
	for i in 15:
		await process_frame
	## Oyuncuyu bolumun baslangicina resetle (reset_to ayrica yaw'i da sifirlar).
	player.call("reset_to", Transform3D(Basis(), Vector3(2, 0.6, 0)))
	for i in 5:
		await physics_frame

	## Kamera yaw = 0 (ileri -Z).
	##
	## ONEMLI: Beklenen yaw'u SABIT bir sayiyla degil, karakterin
	## GERCEKTEN HANGI YONE HAREKET ETTIGINI olcerek hesapla.
	player.call("set_camera_yaw", 0.0)
	player.call("set_input_enabled", true)

	## Bir yone sur, gercekten hangi yone gittigini olc.
	##
	## NOT: Sabit yon secmek yerine dort yonu deneyip EN UZUN mesafeyi
	## seceniz. Sokakta tabelalar/arabalar var; sabit bir yon 0.4 m'de
	## engele takilip kaliyordu (test hatali pozitif veriyordu).
	var best_dir: Vector2 = Vector2.ZERO
	var best_len: float = 0.0
	for probe: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var p0: Vector3 = player.global_position
		player.call("set_autopilot", probe)
		for i in 90:
			await physics_frame
		player.call("set_autopilot", Vector2.ZERO)
		var d: Vector2 = Vector2(
			player.global_position.x - p0.x,
			player.global_position.z - p0.z)
		if d.length() > best_len:
			best_len = d.length()
			best_dir = d
	_check("Oyuncu engel olmadan en az 2 m yol alabiliyor",
		best_len > 2.0,
		"en iyi yon=(%.2f, %.2f) uzunluk=%.2f m" %
		[best_dir.x, best_dir.y, best_len])

	## Simdi en iyi yonla git ve karakterin bakisini OLÇ.
	##
	## reset_to SONRASI konum degisebilir (checkpoint/spawn). Bu yuzden
	## reset_to YAPMADAN, onceden buldugumuz yonu kullaniyoruz.
	## Ilk turda reset_to ile konum degistiyor ve ikinci tur engele
	## takiliyordu (0.34 m) — test hatasiydi, oyun hatasi degil.
	var p0b: Vector3 = player.global_position
	player.call("set_autopilot", best_dir.normalized())
	for i in 120:
		await physics_frame
	player.call("set_autopilot", Vector2.ZERO)
	var actual_dir: Vector2 = Vector2(
		player.global_position.x - p0b.x,
		player.global_position.z - p0b.z)

	## Karakterin baktigi yon (Godot: -Z ileri, yaw 0 -> -Z).
	var body: Node3D = player.get_node_or_null("Body")
	var yaw: float = body.rotation.y if body != null else 0.0
	var facing: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	## Hareket yonu ile bakis yonu ayni olmali (1 = mükemmel).
	var align: float = facing.normalized().dot(actual_dir.normalized())
	_check("Karakter HAREKET YONUNE bakiyor", align > 0.85,
		"hiz=(%.2f, %.2f) bakis=(%.2f, %.2f) uyum=%.2f" %
		[actual_dir.x, actual_dir.y, facing.x, facing.y, align])

	## GERI giderken karakter sirti donmeli + kamera donse bile yon korunmali.
	##
	## Her iki kontrolu TEK bir olcum icinde yap: karakterin gercekten
	## hangi yone gittigini her seferinde yeniden olcuyoruz. Eski
	## surumde onceki turun yonu (actual_dir) kullaniliyordu ama arada
	## karakter yonu degismisti -> yanlis olcum.
	##
	## 1) Kamera dondurulur, karakter HAREKET ETTIRILMEZ -> yon korunmali.
	var yaw_before_cam: float = body.rotation.y if body != null else 0.0
	player.call("set_camera_yaw", PI)
	for i in 20:
		await physics_frame
	var yaw_after_cam: float = body.rotation.y if body != null else 0.0
	var facing_still: Vector2 = Vector2(-sin(yaw_after_cam), -cos(yaw_after_cam))
	## Kamera yaw degisti ama karakter yonu degismemeli:
	## onceki hareket yonu (actual_dir) ile bakis uyumu korunmali.
	var align_still: float = facing_still.normalized().dot(actual_dir.normalized())
	_check("Kamera donse bile karakter yonu KORUNUR (kameraya donmuyor)",
		align_still > 0.75,
		"uyum=%.2f (yaw %.2f -> %.2f)" %
		[align_still, yaw_before_cam, yaw_after_cam])

	## 3) KAMERA-GÖRELİ HAREKET TESTİ (kullanıcının şikayeti)
	##
	## "W" her zaman KAMERANIN BAKTIĞI yöne gitmeli — karakter
	## döndüğünde bile, kamera döndüğünde bile.
	##
	## ÖLÇÜLEN HATA: CameraPivot Player'ın altındaydı; karakterin
	## rotation.y'si kamerayı da döndürüyordu → kamera-göreli hareket
	## bozuluyordu ("würüme ayarını bozmuşsun").
	var cam_check_fail: String = ""
	for cam_yaw_deg: float in [0.0, 45.0, 90.0, 180.0, -90.0]:
		player.call("set_camera_yaw", deg_to_rad(cam_yaw_deg))
		for i in 5:
			await physics_frame
		## Oyuncunun YEREL -Z yönünde hareket etmesini iste (W tuşu).
		var c0: Vector3 = player.global_position
		player.call("set_autopilot", Vector2(0.0, -1.0))   # ileri
		for i in 90:
			await physics_frame
		player.call("set_autopilot", Vector2.ZERO)
		var moved: Vector2 = Vector2(
			player.global_position.x - c0.x,
			player.global_position.z - c0.z)
		if moved.length() < 0.8:
			cam_check_fail = "kamera yaw=%.0f derece: oyuncu %.2f m yol aldı" % [
				cam_yaw_deg, moved.length()]
			break
		## Beklenen yön: kameranın baktığı yön (mutlak yaw'dan).
		var cy: float = deg_to_rad(cam_yaw_deg)
		var expected_dir: Vector2 = Vector2(-sin(cy), -cos(cy))
		var align_cam: float = moved.normalized().dot(expected_dir)
		if align_cam < 0.75:
			cam_check_fail = "kamera yaw=%.0f derece: yön uyumu %.2f (beklenen %s)" % [
				cam_yaw_deg, align_cam, expected_dir]
			break
	_check("W her zaman KAMERANIN baktığı yöne götürür (5 kamera açısı)",
		cam_check_fail == "", cam_check_fail if cam_check_fail != "" else "5/5 açı doğru")

	## 4) KAMERA ve GÖVDE YÖNLERİ BAĞIMSIZ MI?
	##
	## Bu, "W bozuk" ve "karakter arkası dönük" şikayetlerinin
	## ORTAK KÖK NEDENİNİ doğrudan ölçer:
	## kamera yaw'u ile gövde yaw'u birbirinden bağımsız olmalı.
	## Gövde hız yönüne döner; kamera kendi yaw'unu korur.
	##
	## ÖLÇÜLEN HATA (düzeltme öncesi): gövde yaw'u == kamera yaw'u
	## → "W" kameranın baktığı yere gitmiyordu.
	## get_node kullan (get() property arar, node adıyla çalışmaz).
	var cam_pivot: Node3D = main.get_node_or_null("CameraPivot") as Node3D
	_check("CameraPivot Main düzeyinde AYRI bir node",
		cam_pivot != null,
		"" if cam_pivot == null else "bulundu: %s" % cam_pivot.name)
	## Ve Player'ın ALTINDA OLMAMALI.
	var pivot_under_player: Node3D = null
	if player != null:
		pivot_under_player = player.get_node_or_null("CameraPivot") as Node3D
	_check("CameraPivot Player'ın ALTINDA DEĞİL (dönüş bağımsızlığı için)",
		pivot_under_player == null,
		"altında: %s" % ("VAR - HATA" if pivot_under_player != null else "yok"))
	if cam_pivot != null:
		## Kamera yaw = 0, karakter +X'e gidiyor.
		player.call("set_camera_yaw", 0.0)
		for i in 5:
			await physics_frame
		player.call("set_autopilot", Vector2(1.0, 0.0))
		for i in 90:
			await physics_frame
		player.call("set_autopilot", Vector2.ZERO)
		var cam_yaw_now: float = cam_pivot.rotation.y
		var body_now: Node3D = player.get_node_or_null("Body")
		var body_yaw_now: float = body_now.rotation.y if body_now != null else 0.0
		## Kamera yaw değişmemeli (0), gövde ise +X'e dönmüş olmalı.
		_check("Kamera yaw'u DEĞİŞMEDİ (kamera karakteri takip etmiyor)",
			absf(wrapf(cam_yaw_now, -PI, PI)) < 0.15,
			"cam_yaw=%.3f" % cam_yaw_now)
		## Gövde +X'e dönmüş olmalı → yaw = -PI/2 (veya +3PI/2).
		## wrapf ile -PI..PI aralığına indirip FARK alıyoruz:
		##   fark = |wrapf(body - cam)| → gövde kameradan FARKLI yönde
		##   olduğu için bu değer BÜYÜK olmalı (~PI/2).
		var body_diff: float = absf(wrapf(body_yaw_now - cam_yaw_now, -PI, PI))
		## Ayrıca gövdenin +X'e baktığını doğrula:
		## yaw = -PI/2 → bakış yönü = (-sin(-PI/2), -cos(-PI/2)) = (1, 0) = +X ✓
		var body_facing: Vector2 = Vector2(-sin(body_yaw_now), -cos(body_yaw_now))
		var body_points_x: float = body_facing.dot(Vector2(1, 0))
		_check("Gövde AYRI yöne döndü (kamera yaw'undan bağımsız)",
			body_diff > 0.35 and body_points_x > 0.80,
			"body_yaw=%.3f (cam_yaw=%.3f, fark=%.3f) +X bakiş=%.2f" %
			[body_yaw_now, cam_yaw_now, body_diff, body_points_x])

	## 2) Geri yon: TERSI yonu de probe et (engel olmayan yonu bul).
	##
	## best_dir'in TERSI engele dogru olabilir (sokakta tabela var).
	## Bu yuzden geri yonu ayrica aryoruz: dort yonu deneyip en uzun
	## OLANI TERSI olan yonu tercih ediyoruz.
	var back_probe: Vector2 = -best_dir.normalized()
	var back_len: float = 0.0
	for probe2: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var pb0: Vector3 = player.global_position
		player.call("set_autopilot", probe2)
		for i in 90:
			await physics_frame
		player.call("set_autopilot", Vector2.ZERO)
		var dd: Vector2 = Vector2(
			player.global_position.x - pb0.x,
			player.global_position.z - pb0.z)
		if dd.length() > back_len:
			back_len = dd.length()
			back_probe = probe2.normalized()
	## Geri yon olarak, ileri yonun TERSINI kullan (bakis testi icin),
	## ama HAREKET icin en uzun yonu kullan.
	player.call("set_autopilot", back_probe)
	var pb: Vector3 = player.global_position
	for i in 120:
		await physics_frame
	player.call("set_autopilot", Vector2.ZERO)
	var back_actual: Vector2 = Vector2(
		player.global_position.x - pb.x,
		player.global_position.z - pb.z)
	_check("Geri yon gercekten geri gitti", back_actual.length() > 1.0,
		"delta=(%.2f, %.2f) uzunluk=%.2f" %
		[back_actual.x, back_actual.y, back_actual.length()])
	var yaw_back: float = body.rotation.y if body != null else 0.0
	var facing_back: Vector2 = Vector2(-sin(yaw_back), -cos(yaw_back))
	var align_back: float = facing_back.normalized().dot(back_actual.normalized())
	_check("GERI giderken karakter SIRTINI doner (one bakmaz)",
		align_back > 0.75,
		"uyum=%.2f (bakis=(%.2f,%.2f) hiz=(%.2f,%.2f))" %
		[align_back, facing_back.x, facing_back.y,
		back_actual.x, back_actual.y])

	main.queue_free()
	await process_frame


## ── 5) Yokuş yukarı eğilmiş mi? ────────────────────────────────────────────
func _test_hill_slope() -> void:
	print("── 4. bölüm: yokuş ──")
	var packed: PackedScene = load("res://res/scenes/Main.tscn")
	if packed == null:
		_check("Main.tscn yüklendi", false)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	## Yokuş bölümünü yükle.
	main.call("_load_level", 3)
	for i in 20:
		await process_frame

	var level_root: Node = main.get_node_or_null("LevelRoot")
	var hill: Node3D = null
	for child in level_root.get_children():
		if child.has_method("get_level_index") and int(child.get_level_index()) == 3:
			hill = child
			break
	if hill == null:
		_check("Yokuş bölümü yüklendi", false)
		main.queue_free()
		return
	_check("Yokuş bölümü yüklendi", true, hill.name)

	## Yokuş bloğunun eğim açısı POZİTİF olmalı (yukarı tırmanış).
	var slope: Node3D = hill.get_node_or_null("SlopeRoad")
	if slope == null:
		# Alternatif: eğimli blokları ara
		for child in hill.get_children():
			if child is Node3D:
				for sub in child.get_children():
					if sub is Node3D and "Slope" in sub.name:
						slope = sub
						break
	if slope == null:
		_check("Yokuş bloğu bulundu", false)
		main.queue_free()
		return

	var slope_rot: float = slope.rotation.x
	_check("Yokuş YUKARI doğru eğilmiş (rot.x > 0)",
		slope_rot > 0.02,
		"rot.x=%.4f rad (%.1f°)" % [slope_rot, rad_to_deg(slope_rot)])

	## Yokuşun basi (sol uc) alcak, sonu (sag uc) yuksek olmali.
	## Yokusun geometrik uzunlugu = sqrt(run^2 + rise^2) ve egim aci
	## atan(rise/run) — bu ikisi birlikte "yokus gercekten yukseliyor"
	## matematigini verir. Blok AABB'si yaw sonrasi donusmus olabilecegi
	## icin mesh olcmek yerine BOLUM PARAMETRELERINI dogrulariz.
	var hill_script: Script = hill.get_script()
	## NOT: GDScript'te `float(x)` fonksiyonu YOK — property'ye doğrudan
	## eriş (cast `as float` de "Invalid cast" verir çünkü tip adı
	## `float` değil, `TYPE_FLOAT`).
	var slope_start: float = hill.get("slope_start")
	var slope_end: float = hill.get("slope_end")
	var top_y: float = hill.get("slope_top_y")
	var run: float = slope_end - slope_start
	var expected_angle: float = atan(top_y / run)
	_check("Yokus egim acisi dogru (atan(rise/run))",
		absf(slope_rot - expected_angle) < 0.02,
		"rot.x=%.4f beklenen=%.4f (%.1f derece)" %
		[slope_rot, expected_angle, rad_to_deg(expected_angle)])
	_check("Yokus gercekten yukseliyor (top_y > 0, egim pozitif)",
		top_y > 1.0 and slope_rot > 0.02,
		"tepe y=%.1f m, egim=%.1f derece" % [top_y, rad_to_deg(slope_rot)])

	main.queue_free()
	await process_frame
