extends SceneTree
##
## BAŞLATMA AKIŞI TESTİ — "BAŞLA" butonuna basınca oyun açılıyor mu?
## ============================================================================
## Çalıştırma:
##   godot --headless --script res://tools/test_start_flow.gd
##
## Kontroller:
##   1. Prologue görünür mü başta?
##   2. Buton BAŞTA gizli/pasif mi? (beklenen: evet)
##   3. Mesajlar otomatik akıyor mu? (tıklama olmadan)
##   4. Buton beliriyor mu otomatik?
##   5. Butona basınca oyun BAŞLIYOR mu? (state == PLAY)
##   6. Oyuncu hareket edebiliyor mu? (input_enabled)
##   7. Bölüm 0 yüklü mü?
##   8. Prologue gizlendi mi?
##   9. Oyuncu YERDE mi? (düşmemiş)
## ============================================================================

var _main: Node = null
var _player: Node3D = null
var _prologue: CanvasLayer = null
var _game: Node = null
var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\n=== BAŞLATMA AKIŞI TESTİ ===\n")
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  %s%s" % [label, (" -> " + detail) if detail != "" else ""])
	else:
		_failed += 1
		print("  FAIL  %s%s" % [label, (" -> " + detail) if detail != "" else ""])


func _run() -> void:
	var packed: PackedScene = load("res://res/scenes/Main.tscn")
	if packed == null:
		print("HATA: Main.tscn yüklenemedi")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame

	_player = _main.get_node_or_null("Player")
	_prologue = _main.get_node_or_null("Prologue")
	_game = _main.get_node_or_null("GameManager")

	if _player == null or _prologue == null or _game == null:
		print("HATA: player/prologue/game null")
		quit(1)
		return

	# 1) Prologue başta görünür mü?
	var _phone: Control = _prologue.get_node_or_null("PhoneScreen")
	_check("Prologue başta görünür", _phone != null and _phone.visible)

	# 2) Buton başta gizli ve pasif mi?
	var btn: Button = _prologue.get_node_or_null("PhoneScreen/StartButton")
	if btn == null:
		print("HATA: StartButton bulunamadı")
		quit(1)
		return
	_check("Buton BAŞTA gizli", not btn.visible)
	_check("Buton BAŞTA pasif", btn.disabled)

	# 3) Oyun durumu PROLOGUE mu?
	var st_pro: int = int(_game.State.PROLOGUE)
	_check("Oyun durumu PROLOGUE", int(_game.state) == st_pro,
		"state=%d (PROLOGUE=%d)" % [int(_game.state), st_pro])

	# 4) Oyuncu girdisi prologue'da kapalı mı?
	##
	## NOT: Akış artık Main._ready'den başlatılıyor (CanvasLayer'in
	## kendi _ready'si build'de güvenilir çağrılmıyordu).
	_check("Oyuncu girdisi kapalı (prologue'da)",
		not bool(_player.get("input_enabled")))

	# 5) OTOMATİK AKIŞ: hiçbir şeye tıklamadan bekle.
	#    Toplam süre: bildirim 2.2 + mesajlar 3+2.4+2.4 + buton ≈ 11 sn
	print("  ... otomatik akış bekleniyor (20 sn, tıklama YOK)")
	var waited: float = 0.0
	while waited < 20.0 and not btn.visible:
		await create_timer(0.4).timeout
		waited += 0.4

	_check("Buton TIKLAMAYA GEREK KALMADAN belirdi", btn.visible,
		"%.1f sn sonra" % waited)
	_check("Buton aktif (pasif değil)", not btn.disabled)

	# 5b) Buton EKRANDA ve TIKLANABILIR konumda mi?
	# (Eski sürümde buton "görünür" ama 0 boyutluydu → tıklanamıyordu)
	var vp: Vector2 = _prologue.get_viewport().get_visible_rect().size
	var btn_size: Vector2 = btn.size
	var btn_pos: Vector2 = btn.global_position
	_check("Buton GERÇEK BOYUTLU (>= 100x40)",
		btn_size.x >= 100.0 and btn_size.y >= 40.0,
		"%.0f x %.0f" % [btn_size.x, btn_size.y])
	_check("Buton EKRAN İÇİNDE",
		btn_pos.x >= 0 and btn_pos.y >= 0 and
		btn_pos.x + btn_size.x <= vp.x + 10 and
		btn_pos.y + btn_size.y <= vp.y + 10,
		"pos=(%.0f,%.0f) ekran=%.0fx%.0f" %
		[btn_pos.x, btn_pos.y, vp.x, vp.y])
	## Buton EKRANIN ALT YARISINDA olmalı (başlık yukarıda, buton altta).
	##
	## NOT: headless'ta viewport 1280x1280 (gerçek build'de 1280x720).
	## Oran tabanlı kontrol her iki durumda da geçerli.
	_check("Buton ekranın ALT bölgesinde (başlık yukarıda)",
		btn_pos.y > vp.y * 0.35 and btn_pos.y < vp.y * 0.92,
		"y=%.0f / ekran yüksekliği %.0f (oran %.2f)" %
		[btn_pos.y, vp.y, btn_pos.y / maxf(vp.y, 1.0)])
	_check("Buton EN ÜSTTE (z_index >= 100)", btn.z_index >= 100,
		"z_index=%d" % btn.z_index)

	# 5c) Prologue arka planı var mı? (şeffafsa 3D sahne görünür)
	var bg: ColorRect = _prologue.get_node_or_null("PhoneScreen/Background")
	_check("Prologue arka planı VAR (telefon ekranı hissi)",
		bg != null, "" if bg == null else "renk=%s" % bg.color)

	# 6) Butona bas → oyun başlasın.
	_check("Buton sinyal bağlantısı kurulu",
		btn.pressed.is_connected(Callable(_prologue, "_on_start_pressed")))
	btn.emit_signal("pressed")
	await process_frame
	await process_frame

	# 7) Oyun başladı mı?
	_check("Oyun durumu PLAY", int(_game.state) == int(_game.State.PLAY),
		"state=%d" % int(_game.state))

	# 8) Prologue gizlendi mi?
	_check("Prologue gizlendi", _phone != null and not _phone.visible)

	# 9) Oyuncunun girdisi açıldı mı?
	_check("Oyuncu girdisi açıldı", bool(_player.get("input_enabled")))

	# 10) Bölüm 0 yüklü mü?
	var level_root: Node = _main.get_node_or_null("LevelRoot")
	var found: String = ""
	if level_root != null:
		for child in level_root.get_children():
			found += child.name + " "
	_check("Bölüm yüklendi", found.find("Level") >= 0, found.strip_edges())

	# 11) Oyuncu yerde mi? (düşmemiş)
	await create_timer(0.8).timeout
	var py: float = _player.global_position.y
	_check("Oyuncu yerinde (düşmemiş)", py > -1.0, "y=%.2f" % py)

	# 12) Gerçekten oynanabilir mi? (bot yönü ver, hareket et)
	## 120 fizik karesi = 2 saniye.
	##
	## NOT: Ofis bölümünde oyuncu x=2'de başlar ve bu yönde masa/
	## duvar vardır. Bu yüzden mesafe beklentisi düşük tutulur —
	## buradaki amaç "girdi hattı çalışıyor mu" doğrulamak.
	## HEDEFE VARMA testi test_playable.gd'de (4 bölüm, 9/9).
	## Hareket testi SOKAK bölümünde: ofis bölümünde -Z yönünde masa ve
	## duvar var, oyuncu 0.00 m'de takılıp kalıyordu (test hatasıydı).
	##
	## NOT: Hareket yönü artık MUTLAK kamera yaw'undan hesaplanıyor
	## (eski kodda kamera karakterin dönüşünü içeriyordu → "W" bozuktu).
	_main.call("_load_level", 1)
	for i in 15:
		await process_frame
	_player.call("reset_to", Transform3D(Basis(), Vector3(2, 0.6, 0)))
	for i in 5:
		await physics_frame

	_player.call("set_camera_yaw", 0.0)
	_player.call("set_autopilot", Vector2(0, -1))
	var start_pos: Vector3 = _player.global_position
	for i in 120:
		await physics_frame
	_player.call("set_autopilot", Vector2.ZERO)
	var moved_vec: Vector3 = _player.global_position - start_pos
	var moved: float = Vector2(moved_vec.x, moved_vec.z).length()
	_check("Oyuncu HAREKET EDEBİLİYOR (girdi hattı çalışıyor)", moved > 1.0,
		"%.2f m yol aldı (2 sn)" % moved)

	## W tuşu kameranın baktığı yöne götürmeli.
	var expect_dir: Vector3 = Vector3(0, 0, -1)
	var align_move: float = moved_vec.normalized().dot(expect_dir)
	_check("W kameranın baktığı yöne götürür", align_move > 0.7,
		"uyum=%.2f (delta=%s)" % [align_move, moved_vec])

	print("\n=== SONUÇ: %d/%d geçti ===\n" % [_passed, _passed + _failed])
	quit(0 if _failed == 0 else 1)
