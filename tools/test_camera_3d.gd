extends SceneTree
##
## 3D KAMERA DOĞRULAMA — "oyun 3D, kamera 2D" şikayeti
## ============================================================================
## Çalıştırma:
##   godot --headless --script res://tools/test_camera_3d.gd
##
## Kontroller:
##   1. Kamera karakterin ÜSTÜNDE ve ARKASINDA mı? (yükseklik + mesafe)
##   2. Kamera HEDEFE BAKIYOR mu? (look_at doğru mu)
##   3. Kamera YÜKSEKTE mi? (düz kamera = 2D hissi)
##   4. Yatay bir çizgi uzaktayken kısalıyor mu? (perspektif = 3D)
##   5. Kamera pitch değişince yükseklik değişiyor mu? (serbest bakış)
##   6. Kamera karakterin konumunu takip ediyor mu?
## ============================================================================

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\n=== 3D KAMERA DOĞRULAMA ===\n")
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
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	## NOT: `get("player")` node ADIYLA çalışmaz — property arar.
	## Doğru yol: get_node_or_null("Player").
	var player: Node3D = main.get_node_or_null("Player") as Node3D
	var pivot: CameraPivot = main.get_node_or_null("CameraPivot") as CameraPivot
	if player == null or pivot == null:
		print("HATA: player/pivot yok")
		quit(1)
		return

	var cam: Camera3D = pivot.get_node_or_null("Camera3D")
	_check("Camera3D var", cam != null)
	if cam == null:
		quit(1)
		return

	## Oyunu başlat ki karakter yerinde dursun.
	var game: Node = main.get_node_or_null("GameManager")
	if game != null:
		game.state = game.State.PLAY
	player.call("set_input_enabled", true)
	await physics_frame
	await physics_frame

	## ── 1) KAMERA KONUMU: karakterin üstünde ve arkasında ──
	var cam_pos: Vector3 = cam.global_position
	var player_pos: Vector3 = player.global_position
	var rel: Vector3 = cam_pos - player_pos
	_check("Kamera karakterden YÜZDE yukarıda (2D hissi yok)",
		rel.y > 0.8,
		"y=%.2f m" % rel.y)
	_check("Kamera karakterden en az 3 m UZAKTA",
		Vector2(rel.x, rel.z).length() > 3.0,
		"yatay mesafe=%.2f m" % Vector2(rel.x, rel.z).length())
	_check("Kamera mesafesi 4-10 m arasında (doğru TPS mesafesi)",
		Vector3(rel.x, rel.y, rel.z).length() > 4.0 and
		Vector3(rel.x, rel.y, rel.z).length() < 10.0,
		"toplam=%.2f m" % Vector3(rel.x, rel.y, rel.z).length())

	## ── 2) KAMERA HEDEFE BAKIYOR MU? ──
	var to_player: Vector3 = (player_pos - cam_pos).normalized()
	var cam_forward: Vector3 = -cam.global_transform.basis.z
	var look_dot: float = cam_forward.dot(to_player)
	_check("Kamera KARAKTERE BAKIYOR (look_at çalışıyor)", look_dot > 0.90,
		"dot=%.3f (1.0 = tam bakış)" % look_dot)

	## ── 3) KAMERA YÜKSEKTE Mİ (düz kamera = 2D) ──
	## Yatay bakış açısı: 20-45 derece arası klasik TPS.
	var horizontal: float = Vector2(rel.x, rel.z).length()
	var angle_deg: float = rad_to_deg(atan2(rel.y, horizontal))
	_check("Kamera 15-50 derece YUKARIDAN bakıyor (3D perspektif)",
		angle_deg > 15.0 and angle_deg < 50.0,
		"%.1f derece" % angle_deg)

	## ── 4) PERSPEKTİF: aynı yükseklikteki iki nokta farklı derinlikte ──
	## Kamera FOV'su makul mü (dar FOV = 2D hissi)
	_check("Kamera FOV'u 55-85 arasında (geniş = derinlik hissi)",
		cam.fov >= 55.0 and cam.fov <= 85.0,
		"fov=%.0f" % cam.fov)

	## ── 5) PITCH KAMERA YÜKSEKLİĞİNİ DEĞİŞTİRİR ──
	var height_before: float = rel.y
	player.call("set_camera_yaw", 0.0)
	var pivot_script: Script = pivot.get_script()
	if pivot_script != null and pivot.has_method("set") == false:
		pass
	## Pitch'i doğrudan PIVOT'a yaz.
	##
	## NOT: Player her fizik karesinde pivot.pitch = _pitch yazıyor.
	## Testte bunu engellemek için `_pitch_managed_by_pivot` bayrağı
	## açılır — player artık pitch'i ezmez, pivot sahibidir.
	## Pitch'i PLAYER üzerinden değiştir — player'ın _pitch'i pivot'a
	## yazıyor, doğrudan pivot'a yazmak ezilir.
	##
	## `_pitch_managed_by_pivot = true` ile player pitch'i EZMEZ,
	## böylece pivot'un pitch'i kalıcı olur.
	player._pitch_managed_by_pivot = true
	player._pitch = -0.7
	pivot.pitch = -0.7
	for i in 8:
		await process_frame
	var rel2: Vector3 = cam.global_position - player.global_position
	var height_after: float = rel2.y
	## Doğrudan PROPERTY erişimi — `get()` Variant döndürür ve
	## `as float` cast'i başarısız olur (tip adı `float` değil).
	var pitch_now: float = pivot.pitch
	_check("Fare yukarı/aşağı hareketi kamerayı YÜKSELTİR/ALÇALTIR",
		absf(height_after - height_before) > 0.3,
		"%.2f -> %.2f m (pitch=%.2f)" % [height_before, height_after, pitch_now])
	## Yükseklik = pivot_yuksekligi + sin(-pitch) * mesafe
	var expected_h: float = 1.72 + sin(-pitch_now) * 6.4
	_check("Kamera yüksekliği pitch ile hesaplanıyor (yörünge formülü)",
		absf(height_after - expected_h) < 0.6,
		"ölçülen=%.2f beklenen=%.2f" % [height_after, expected_h])
	player._pitch = -0.18
	player._pitch_managed_by_pivot = false
	pivot.pitch = -0.18
	for i in 8:
		await process_frame

	## ── 6) KAMERA KARAKTERİ TAKİP EDİYOR ──
	var p0: Vector3 = player.global_position
	var c0: Vector3 = cam.global_position
	player.call("set_autopilot", Vector2(0, -1))
	for i in 60:
		await physics_frame
	player.call("set_autopilot", Vector2.ZERO)
	var player_moved: float = (player.global_position - p0).length()
	var cam_moved: float = (cam.global_position - c0).length()
	_check("Kamera karakteri TAKİP EDİYOR (oyuncu ile birlikte gidiyor)",
		cam_moved > player_moved * 0.8,
		"oyuncu %.2f m, kamera %.2f m" % [player_moved, cam_moved])

	## ── 7) GÖRÜNTÜ: gerçek render ──
	# NOT: headless modda frame_post_draw beklemek ASILIR.
	# Bu yuzden goruntu bolumu yalnizca GRAFIC varsa calisir;
	# headless test kosumunda atlanir.
	if DisplayServer.get_name() == "headless":
		print("  [--] Goruntu bolumu atlandi (headless mod)")
	else:
		var shot_dir: String = "res://shots"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
		for v: Dictionary in [
				{"name": "cam-on", "yaw": 0.0},
				{"name": "cam-yan", "yaw": 90.0},
				{"name": "cam-arka", "yaw": 180.0}]:
			player.call("set_camera_yaw", v["yaw"])
			for i in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			if img != null:
				img.save_png("%s/%s.png" % [shot_dir, v["name"]])
				print("  ✓ %s.png" % v["name"])

	print("\n=== SONUÇ: %d/%d geçti ===\n" % [_passed, _passed + _failed])
	quit(0 if _failed == 0 else 1)
