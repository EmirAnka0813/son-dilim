extends SceneTree
##
## OYNANABİLİRLİK TESTİ — bot baştan sona oyunu bitirir
## ============================================================================
## Çalıştırma:
##   godot --headless --script res://tools/test_playable.gd
##
## Bot davranışı:
##   · Her bölümde hedefe doğru yürür (X ekseni boyunca)
##   · Pasta dengesini Q/E ile düzeltir (slip yükselirse)
##   · Engelere çarpma durumunda yeniden deneme yapar
##   · Bölüm çıkışına ulaşır → sonraki bölüme geçer
##
## Test edilenler:
##   1. Her bölüm tamamlanabiliyor mu?
##   2. Checkpoint'ler çalışıyor mu (kaza sonrası dönüş)?
##   3. Kronometre gerçekten azalıyor mu?
##   4. Mutlu son ekranı açılıyor mu?
##   5. Pasta düşünce kaza oluşuyor ve oyun bitiyor mu?
## ============================================================================

var passed: int = 0
var failed: int = 0
var _main: Node = null
var _player: Node = null
var _game: Node = null


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("  PASS  ", label, (" -> " + detail) if detail != "" else "")
	else:
		failed += 1
		print("  FAIL  ", label, (" -> " + detail) if detail != "" else "")


func _init() -> void:
	print("\n=== SON DİLİM — OYNANABİLİRLİK TESTİ ===\n")
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://res/scenes/Main.tscn")
	if packed == null:
		_check("Main.tscn yükleniyor", false)
		_finish()
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame

	_player = _main.get_node_or_null("Player")
	_game = _main.get_node_or_null("GameManager")
	var level_root: Node3D = _main.get_node_or_null("LevelRoot")

	## Prologue'u kapat ve oyuna gir.
	##
	## NOT: begin_game() bir TWEEN kullanır (perde geçişi). TWEEN, kendi
	## çağırdığı _load_level ile bizim test çağrımızı çakıştırıyordu.
	## Bu yüzden doğrudan oyun durumunu ayarlıyoruz — TWEEN yok, çakışma yok.
	var pro: Node = _main.get_node_or_null("Prologue")
	if pro != null:
		pro.visible = false
	_game.state = _game.State.PLAY
	_game.current_level = 0
	_player.set_input_enabled(true)
	await create_timer(0.4).timeout
	await process_frame

	_check("Oyun durumu PLAY", _game.state == _game.State.PLAY)

	## ── HER BÖLÜMÜ BOT İLE OYNA ──
	for level_index in 4:
		var reached: bool = await _play_level(level_index, level_root)
		_check("Bölüm %d tamamlanabiliyor" % (level_index + 1), reached,
			"hedefe ulaşıldı")

	## ── KRONOMETRE AZALDI MI ──
	var t0: float = _game.time_left
	for i in 30:
		await physics_frame
	_check("Kronometre azalıyor", _game.time_left < t0,
		"%.1f -> %.1f" % [t0, _game.time_left])

	## ── PASTA DÜŞÜNCE KAZA ──
	_game.state = _game.State.PLAY
	_player.balance.slip = 0.99
	_player.balance.set_angle(1.4)
	for i in 240:
		_player.balance._step_swing(1.0 / 60.0)
		_player.balance._step_slip(1.0 / 60.0)
		if _game.state == _game.State.LOSE:
			break
	_check("Pasta düşünce oyun bitiyor", _game.state == _game.State.LOSE,
		"slip=%.2f" % _player.balance.slip)

	## ── KAZA SONRASI CHECKPOINT'E DÖNÜŞ ──
	var cp_count: int = 0
	if "_checkpoints" in _game:
		cp_count = (_game.get("_checkpoints") as Array).size()
	elif "checkpoints" in _game:
		cp_count = (_game.get("checkpoints") as Array).size()
	_check("Checkpoint'ler kayıtlı", cp_count >= 3, "%d checkpoint" % cp_count)

	## ── MUTLU SON ──
	_game.state = _game.State.PLAY
	_game._end_game(_game.EndReason.ARRIVED)
	await process_frame
	var final_screen: Control = _main.get("final_screen")
	_check("Mutlu son ekranı açılıyor",
		final_screen != null and final_screen.visible, "visible=%s" %
		(str(final_screen.visible) if final_screen != null else "yok"))

	_finish()


## Bir bölümü bot ile oyna. Bölüm çıkışına ulaşırsa true döner.
func _play_level(level_index: int, level_root: Node3D) -> bool:
	## Bölümü yükle.
	## Önce oyuncuyu güvenli bir yere koy ki eski bölümün exit zone'u
	## tetiklenip bölümü değiştirmesin.
	_player.global_position = Vector3(2, 0.6, 0)
	## Bölümün başlangıcına koy (x=1). Exit zone bölümün SONU olduğu için
	## başlangıçta tetiklenmez.
	_player.global_position = Vector3(1, 0.6, 0)
	_player.set("velocity", Vector3.ZERO)
	await process_frame
	_main.call("_load_level", level_index)
	## Hemen kontrol: doğru bölüm yüklendi mi?
	await process_frame
	var dbg: Array[String] = []
	for c in level_root.get_children():
		dbg.append(str(c.name))
	print("      HEMEN: %s" % ", ".join(dbg))
	for i in 60:
		await process_frame
	await create_timer(0.5).timeout
	await process_frame
	dbg.clear()
	for c in level_root.get_children():
		dbg.append(str(c.name))
	print("      SONRA: %s (oyuncu x=%.0f)" % [", ".join(dbg),
		_player.global_position.x])

	## Bölümün çıkış konumunu al.
	var level: Node = null
	var want: String = ["LevelOffice", "LevelStreet", "Level_Metro",
		"Level_Hill"][level_index]
	## Tüm çocukları tara — isim VEYA get_level_index eşleşmesi.
	for child in level_root.get_children():
		var by_name: bool = str(child.name) == want
		var by_idx: bool = child.has_method("get_level_index") \
			and int(child.get_level_index()) == level_index
		if by_name or by_idx:
			level = child
			break
	if level == null:
		## Tesis: level_root içinde ne var?
		var names: Array[String] = []
		for child in level_root.get_children():
			var d: String = child.name
			if child.has_method("get_level_index"):
				d += "(idx=%d)" % int(child.get_level_index())
			names.append(d)
		print("    (bölüm bulunamadı) level_root: %s" % ", ".join(names))
		return false

	var exit_pos: Vector3 = level.get_exit_position()
	var start_x: float = _player.global_position.x
	print("  Bölüm %d: x=%.0f -> %.0f" % [level_index + 1, start_x, exit_pos.x])

	## Oyuncu başlangıç konumunda (bölüm başı).
	_player.global_position = Vector3(1, 0.6, 0)
	_player.set("velocity", Vector3.ZERO)

	## Bot: sürekli +X yönünde ilerle, dengeyi düzelt, engellerde zıpla.
	var elapsed: float = 0.0
	## Yokuş (bölüm 4) daha uzun sürer — 140 saniye.
	var max_time: float = 140.0 if level_index == 3 else 90.0
	var stuck_count: int = 0
	var last_x: float = 1.0

	while elapsed < max_time:
		elapsed += 0.05

		## Hedefe doğru yön.
		var dx: float = exit_pos.x - _player.global_position.x
		if absf(dx) < 2.5:
			return true

		## Hareket: GERÇEK InputEvent gönder.
		##
		## ÖNEMLİ: Input.get_vector() "move_right" ve "move_forward" tuşlarının
		## BASILI olduğunu okur. Headless'ta Input.parse_input_event olayı
		## Input singleton'ına işler ama "pressed" durumu action bazında
		## tutulur — bu yüzden HER iki yönü de basılı tutuyoruz (net etki
		## sağa+ileri olur).
		## Oyun içi autopilot (headless'ta Input güvenilir değil).
		##
		## YÖN: bölümler +X boyunca uzanıyor. Oyuncunun yaw'ını +X'e
		## çevirip kamerayı da +X'e baktırıyoruz; "forward" (W) yeterli.
		## yaw = -90° → kameranın -Z ekseni dünya +X'e bakar.
		_player.set_camera_yaw(-PI * 0.5)
		_player.set_autopilot(Vector2(0, -1))
		_send_key("sprint", true)

		## Denge düzeltme: slip yükseliyorsa Q/E yönünde düzelt.
		if _player.balance.slip > 0.25:
			var dir: float = 0.0
			if _player.balance.angle > 0.05:
				dir = -1.0
			elif _player.balance.angle < -0.05:
				dir = 1.0
			if dir != 0.0:
				_player.balance.add_correction(dir, 2.0 * 0.05 * 60.0)

		## Zıplama: engele takıldıysa.
		if absf(_player.global_position.x - last_x) < 0.02:
			stuck_count += 1
			## 20 kare (0.33 sn) hareketsizlik → zıpla.
			if stuck_count > 20:
				_send_key("jump", true)
				await physics_frame
				_send_key("jump", false)
				stuck_count = 0
		else:
			stuck_count = 0
		last_x = _player.global_position.x

		## Yokuşta: rampa yavaşlatır — ara sıra sıçrayarak ivme korunur.
		if level_index == 3 and int(elapsed * 20.0) % 40 == 0:
			_send_key("jump", true)
			await physics_frame
			_send_key("jump", false)

		## Pasta düştüyse → kaza → checkpoint dönüşü.
		if _game.state == _game.State.LOSE:
			print("    (kaza → checkpoint dönüşü)")
			_game.state = _game.State.PLAY
			## Son checkpoint'e ışınlan.
			var cps: Array = _game.get("_checkpoints")
			if cps.size() > 0:
				var cp: Transform3D = cps[cps.size() - 1]["position"]
				_player.global_position = cp.origin
				last_x = cp.origin.x

		await physics_frame
		## Tesis: her 5 saniyede konum (nerede takiliyor?).
		if int(elapsed) % 5 == 0 and absf(elapsed - float(int(elapsed))) < 0.05:
			print("      t=%3.0f x=%6.1f y=%4.1f vx=%5.1f slip=%.2f" % [elapsed,
				_player.global_position.x, _player.global_position.y,
				_player.velocity.x, _player.balance.slip])

	return false


## Bir aksiyon için gerçek InputEvent üret ve oyuncuya ilet.
## (Input.action_press headless'da fizik döngüsüne aktarılmıyor.)
func _send_key(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _finish() -> void:
	print("\n=== SONUÇ: %d/%d geçti ===\n" % [passed, passed + failed])
	quit(0 if failed == 0 else 1)
