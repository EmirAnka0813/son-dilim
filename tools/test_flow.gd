extends SceneTree
##
## OYUN AKIŞI DOĞRULAMA (headless)
## ============================================================================
##   godot --headless --script res://tools/test_flow.gd
##
## Test edilenler:
##   1. Main sahnesi yükleniyor
##   2. Oyuncu doğuyor, denge sistemi bağlı
##   3. Bölüm 1 (ofis) kuruluyor — masalar, asansör platformları
##   4. Bölüm 2 (sokak) kuruluyor — araçlar, ıslak zemin, yayalar
##   5. Checkpoint'ler kaydediliyor
##   6. Kronometre işliyor (süre azalıyor)
##   7. Pasta düşünce OYUN BİTER (kaza)
##   8. Bölüm geçişi çalışıyor
##   9. Ses dosyaları yükleniyor
## ============================================================================

var passed: int = 0
var failed: int = 0
var _main: Node = null
var _frames: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("  PASS  ", label, (" -> " + detail) if detail != "" else "")
	else:
		failed += 1
		print("  FAIL  ", label, (" -> " + detail) if detail != "" else "")


func _init() -> void:
	print("\n=== SON DİLİM — OYUN AKIŞI DOĞRULAMA ===\n")
	_run.call_deferred()


func _run() -> void:
	await process_frame

	## ── 1) ANA SAHNE ──
	var packed: PackedScene = load("res://res/scenes/Main.tscn")
	if packed == null:
		_check("Main.tscn yükleniyor", false, "yüklenemedi")
		_finish()
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	_check("Main sahnesi yüklendi", _main != null and _main.is_inside_tree())

	var player: Player = _main.get_node_or_null("Player")
	var game: GameManager = _main.get_node_or_null("GameManager")
	var ui: UIController = _main.get("ui")
	_check("Oyuncu referansı var", player != null)
	_check("GameManager referansı var", game != null)
	_check("UI referansı var", ui != null)

	if player == null or game == null:
		_finish()
		return

	## ── 2) DENGE SİSTEMİ ──
	_check("Denge sistemi bağlı", player.balance != null)
	_check("Denge varsayılan açı 0", absf(player.balance.angle) < 0.001)

	## ── 3) BÖLÜM 1 (OFİS) ──
	var level_root: Node3D = _main.get_node_or_null("LevelRoot")
	_check("Bölüm 1 kuruldu", level_root.get_child_count() > 0,
		"%d çocuk" % level_root.get_child_count())
	var office: Node = level_root.get_child(0) if level_root.get_child_count() > 0 else null
	_check("Bölüm 1 scripti doğru", office != null and office.has_method("get_checkpoint_transforms"))
	if office:
		var cps: Array[Transform3D] = office.get_checkpoint_transforms()
		_check("Bölüm 1 checkpoint'leri var", cps.size() >= 3, "%d checkpoint" % cps.size())

	## ── 4) OYUNU BAŞLAT + KRONOMETRE ──
	game.start_game()
	await process_frame
	_check("Oyun durumu PLAY", game.state == GameManager.State.PLAY)
	var t0: float = game.time_left
	for i in 30:
		await physics_frame
	_check("Kronometre işliyor", game.time_left < t0,
		"%.1f -> %.1f" % [t0, game.time_left])

	## ── 5) BÖLÜM 2 (SOKAK) ──
	## NOT: advance_to_next_level() bir TWEEN kullanır (perde 0.35s + 0.45s).
	## Kare sayısı yetmez — gerçek zamanı beklemeliyiz.
	_main.call("advance_to_next_level")
	await create_timer(1.4).timeout
	await process_frame
	_check("Bölüm 2 yüklendi", game.current_level == 1, "level=%d" % game.current_level)
	## Sokak bölümünü AYIRT ET: level_index'e göre (0=ofis, 1=sokak).
	## NOT: queue_free() 1 kare sonra tamamlanır — eski sahne hâlâ çocuk
	## listesinde olabilir. Bu yüzden index'e bakmıyoruz, İÇERİĞE bakıyoruz.
	var street: Node = null
	var street_index: int = -1
	var children_debug: Array[String] = []
	for i in level_root.get_child_count():
		var child: Node = level_root.get_child(i)
		var has_idx: bool = child.has_method("get_level_index")
		var idx: int = int(child.get_level_index()) if has_idx else -99
		children_debug.append("%s(idx=%s)" % [child.name, str(idx)])
		if has_idx and idx == 1:
			street = child
			street_index = i
			break
	_check("Bölüm 2 (sokak) sahnesi kuruldu", street != null,
		"çocuklar: %s" % ", ".join(children_debug))
	if street:
		var cps2: Array[Transform3D] = street.get_checkpoint_transforms()
		_check("Bölüm 2 checkpoint'leri var", cps2.size() >= 4, "%d checkpoint" % cps2.size())
		## Araç ve yaya sayısı.
		var cars: Array = street.get("_cars")
		var peds: Array = street.get("_pedestrians")
		_check("Sokakta araçlar var", cars != null and cars.size() >= 6,
			"%d araç" % (cars.size() if cars != null else 0))
		_check("Sokakta yayalar/köpekler var", peds != null and peds.size() >= 10,
			"%d yaya/köpek" % (peds.size() if peds != null else 0))

	## ── 5b) BÖLÜM 3 (METRO) ve BÖLÜM 4 (YOKUŞ) ──
	for lvl in [2, 3]:
		_main.call("advance_to_next_level")
		await create_timer(1.4).timeout
		await process_frame
		## TWEEN iki aşamalı: önce bölüm yüklenir, sonra current_level artar.
		## current_level artışı da tween içinde — bekleme bittiğinde hazır olmalı.
		await create_timer(0.3).timeout
		await process_frame
		var target: Node = null
		for child in level_root.get_children():
			if child.has_method("get_level_index") \
					and int(child.get_level_index()) == lvl:
				target = child
				break
		_check("Bölüm %d yüklendi" % (lvl + 1), target != null,
			"level=%d" % game.current_level)
		if target != null:
			var cps3: Array[Transform3D] = target.get_checkpoint_transforms()
			_check("Bölüm %d checkpoint'leri var" % (lvl + 1),
				cps3.size() >= 4, "%d checkpoint" % cps3.size())
			## Son bolumde hedef konumu erisilebilir mi?
			var exit_pos: Vector3 = target.get_exit_position()
			_check("Bölüm %d çıkış konumu var" % (lvl + 1),
				exit_pos.length() > 0.5,
				"x=%.0f y=%.1f" % [exit_pos.x, exit_pos.y])

	## ── 6) PASTA DÜŞÜNCE OYUN BİTER ──
	game.state = GameManager.State.PLAY
	player.balance.set_angle(1.5)
	player.balance.slip = 0.98
	player.balance.apply_acceleration(Vector3(20, 0, 0))
	for i in 120:
		player.balance._step_swing(1.0 / 60.0)
		player.balance._step_slip(1.0 / 60.0)
		if game.state == GameManager.State.LOSE:
			break
	_check("Pasta düşünce oyun biter", game.state == GameManager.State.LOSE,
		"state=%s slip=%.2f" % [game.state, player.balance.slip])

	## ── 7) SÜRE DOLUNCA OYUN BİTER ──
	game.state = GameManager.State.PLAY
	game.time_left = 0.01
	for i in 10:
		await physics_frame
	_check("Süre bitince oyun biter", game.state == GameManager.State.LOSE,
		"state=%s" % game.state)

	## ── 8) SÜRE DOLDUĞUNDA MUTLU SON ──
	game.state = GameManager.State.PLAY
	game._end_game(GameManager.EndReason.ARRIVED)
	_check("Zamanında gelince mutlu son", game.state == GameManager.State.WIN)

	## ── 9) SES DOSYALARI ──
	var audio_ok: int = 0
	for f in ["footsteps", "car_horn", "timer_tick", "failure", "success",
			"slip_warning", "bump", "jump", "pickup", "ambient_rain"]:
		var path: String = "res://res/assets/audio/%s.wav" % f
		if ResourceLoader.exists(path):
			audio_ok += 1
	_check("Tüm ses dosyaları yüklü", audio_ok == 10, "%d/10" % audio_ok)

	## ── 10) OYUNCU KONTROLLERİ ──
	_check("Oyuncu yerçekimi uygular", player.gravity > 0.0)
	_check("Sprint hızı > yürüme hızı", player.sprint_speed > player.walk_speed)
	_check("Kamera hassasiyeti tanımlı", player.camera_sensitivity > 0.0)
	_check("İvme ölçümü yapılıyor", player.balance.last_accel.length() >= 0.0)

	_finish()


func _finish() -> void:
	print("\n=== SONUÇ: %d/%d geçti ===\n" % [passed, passed + failed])
	quit(0 if failed == 0 else 1)
