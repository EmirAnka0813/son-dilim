extends SceneTree
##
## KARAKTER GÖRSEL DOĞRULAMA
## ============================================================================
## Çalıştırma:
##   godot --resolution 900x900 --path . --script res://tools/test_character.gd
##
## Kontroller:
##   · Karakter AYAKTA mı? (mesh Y ekseni en uzun mu?)
##   · Karakterin yüzü kameraya dönük mü?
##   · Pasta kutusu ELDE mi? (göğüs hizasında, önde)
##   · Kutu boyutu "devasa" mı?
##   · Eller kutuyu kavrayacak kadar yakın mı?
##
## Çıktı: res://shots/char-*.png (4 açıdan)
##
## NOT: Ölçüm RECURSIVE olmak zorunda. Bir GLB instance'ının mesh'leri
## doğrudan çocuk değil, daha derin bir node'da olabilir. Sadece
## get_children() ile ölçmek yanlış sonuç verir (ölçülen: y=0.64m, gerçek: 2.27m).
## ============================================================================

var _main: Node = null
var _player: Node3D = null
var _cam: Camera3D = null
var _out: String = "res://shots"


func _init() -> void:
	print("\n=== KARAKTER GÖRSEL DOĞRULAMA ===\n")
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

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
	if _player == null:
		print("HATA: player yok")
		quit(1)
		return

	_cam = Camera3D.new()
	_cam.fov = 45.0
	_cam.near = 0.02
	_cam.far = 100.0
	_cam.current = true
	root.add_child(_cam)

	## Aydınlatma — karakter testi için izole ışık (3 nokta).
	## Karakter y=40'ta havada durduğu için bölüm ışıkları ulaşmaz.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.95, 0.88)
	key.light_energy = 2.2
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-35, 35, 0)
	root.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.65, 0.75, 1.0)
	fill.light_energy = 1.1
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-20, -140, 0)
	root.add_child(fill)

	## NOT: DirectionalLight konumdan bağımsızdır (yön önemli) — ışık yeter.

	##
	## IŞIKLAR: Karakter y=40'ta HAVADA duruyor. Bölüm ışıkları
	## (y=0-5) 40 m ötede kalıyor → kare siyah çıkıyor.
	## Işıkları doğrudan karakterin YANINA koy.
	##
	## Key light: karakterin önünde-üstünde, sıcak.
	var key2 := OmniLight3D.new()
	key2.light_color = Color(1.0, 0.95, 0.86)
	key2.light_energy = 14.0
	key2.omni_range = 16.0
	key2.position = Vector3(0, 42.0, -3.0)
	root.add_child(key2)

	## Fill: arkadan, soğuk (silueti ayırır).
	var fill2 := OmniLight3D.new()
	fill2.light_color = Color(0.70, 0.80, 1.0)
	fill2.light_energy = 9.0
	fill2.omni_range = 16.0
	fill2.position = Vector3(-2.5, 41.0, 3.0)
	root.add_child(fill2)

	## Arka plan rengi (siyah yerine açık gri — siluet net görünsün).
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.28, 0.30, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.45, 0.55)
	env.ambient_light_energy = 2.2
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	## Karakteri havada tut (zemin gormesin).
	_player.global_position = Vector3(0, 10, 0)
	var game: Node = _main.get_node_or_null("GameManager")
	if game != null:
		game.state = game.State.PLAY
	await process_frame

	var checks: Array[Dictionary] = []

	## ── 1) KARAKTER BEDENİ ──
	var char_node: Node3D = _player.get_node_or_null("Body/Character")
	if char_node != null:
		var bounds: Array = _measure_bounds(char_node)
		var mn: Vector3 = bounds[0]
		var mx: Vector3 = bounds[1]
		var size: Vector3 = mx - mn
		var height: float = size.y
		var width: float = size.x
		var depth: float = size.z
		var center_x: float = (mn.x + mx.x) * 0.5
		print("  Karakter bedeni: x=%.2f y=%.2f z=%.2f (yukseklik %.2fm)" %
			[width, height, depth, height])

		checks.append({
			"label": "Karakter AYAKTA (Y boyutu en buyuk, > 1.5m)",
			"ok": height > 1.5 and height > width and height > depth,
			"detail": "yukseklik=%.2fm x=%.2f z=%.2f" % [height, width, depth],
		})
		## NOT: Gövde artık hareket yönüne döner (kameraya değil), bu
		## yüzden merkez X küçük bir kaymaya olabilir. Karakterin kendi
		## yerel ekseninde dikeyle olduğunu kontrol etmek daha doğru:
		## Y boyutu en uzun (zaten ayrı bir kontrolde var) ve gövdenin
		## Y ekseni dünya dikeyine paralel.
		var up_dot: float = 0.0
		if char_node != null:
			var basis: Basis = char_node.global_transform.basis
			up_dot = basis.y.normalized().dot(Vector3.UP)
		checks.append({
			"label": "Karakter dikeyle duruyor (gövde Y ekseni dikey)",
			"ok": up_dot > 0.98,
			"detail": "Y ekseni dikey ile açı=%.3f (dot=%.3f)" %
				[acos(clampf(up_dot, -1.0, 1.0)), up_dot],
		})
		checks.append({
			"label": "Karakterin yuzu -Z yonune bakiyor (Godot ileri yonu)",
			"ok": _face_points_forward(char_node),
			"detail": "yuz yonu: %s" % ("-Z (dogru)" if _face_points_forward(char_node) else "+Z (ters)"),
		})

		## ── 2) PASTA KUTUSU ──
		var cake: Node3D = _player.get_node_or_null("CakeBox")
		if cake != null:
			var rel: Vector3 = cake.global_position - _player.global_position
			checks.append({
				"label": "Pasta kutusu ELDE (gogus hizasi 1.0-1.5m)",
				"ok": rel.y > 1.0 and rel.y < 1.5,
				"detail": "y=%.2f" % rel.y,
			})
			checks.append({
				"label": "Pasta kutusu ONDE (z>0, sirtta degil)",
				"ok": rel.z > 0.15,
				"detail": "z=%.2f" % rel.z,
			})

			var box_node: Node3D = cake.get_node_or_null("Mesh")
			if box_node != null:
				var bb: Array = _measure_bounds(box_node)
				var bw: float = (bb[1] as Vector3).x - (bb[0] as Vector3).x
				var bh: float = (bb[1] as Vector3).y - (bb[0] as Vector3).y
				checks.append({
					"label": "Kutu DEVASA (genislik >= 0.50m, yukseklik >= 0.40m)",
					"ok": bw >= 0.50 and bh >= 0.40,
					"detail": "%.2f x %.2f m" % [bw, bh],
				})

				## ── 3) ELLER ──
				var hands: Array[Vector3] = []
				_collect_hands(char_node, hands)
				if hands.size() >= 2:
					var min_d: float = 999.0
					for h: Vector3 in hands:
						min_d = minf(min_d, h.distance_to(cake.global_position))
					checks.append({
						"label": "Eller kutuyu kavrayacak yakinlikta (<0.45m)",
						"ok": min_d < 0.45,
						"detail": "en yakin el-kutu = %.2fm (%d el)" % [min_d, hands.size()],
					})
				else:
					checks.append({
						"label": "Eller kutuyu kavrayacak yakinlikta",
						"ok": false,
						"detail": "sadece %d el bulundu" % hands.size(),
					})

	## ── RAPOR ──
	var passed: int = 0
	var failed: int = 0
	for c: Dictionary in checks:
		if c["ok"]:
			passed += 1
			print("  PASS  %s -> %s" % [c["label"], c["detail"]])
		else:
			failed += 1
			print("  FAIL  %s -> %s" % [c["label"], c["detail"]])

	## ── GÖRÜNTÜLER ──
	##
	## ÖNEMLİ: Karakter HAREKET ETTİRİLEREK çekilir. Çünkü asıl sorun
	## "karakter arkası dönük yürüyor" idi — hareketsiz karakter her
	## açıdan aynı görünür ve sorun görünmez.
	##
	## Her görüntü için: karakter bir yöne yürür, kamera o yönün
	## arkasından çekilir → karakterin YÜZÜ görünür mü kontrol edilir.
	var views: Array[Dictionary] = [
		{"name": "char-on", "offset": Vector3(0, 0.5, -2.6), "move": Vector2(0, -1)},
		{"name": "char-yan", "offset": Vector3(2.6, 0.5, 0), "move": Vector2(1, 0)},
		{"name": "char-arka", "offset": Vector3(0, 0.5, 2.6), "move": Vector2(0, 1)},
		{"name": "char-ust", "offset": Vector3(0, 2.8, -0.5), "move": Vector2(0, -1)},
	]
	## GÖRÜNTÜ: Karakteri kadraja al.
	##
	## look_at() hedefe bakar — AMA CharacterBody3D'nin Y ekseni yerine
	## mesh'in ayak pozisyonunu hedef al. Karakter y=10'da, kamera da
	## orada. offset'ler 3.4m — kadraj dolu olmalı.
	for v: Dictionary in views:
		var off: Vector3 = v["offset"]
		## Karakteri HAREKET ettir (yön testi için).
		## Kamera yaw'ı, karakterin gideceği yöne bakacak şekilde ayarla.
		var move_dir: Vector2 = v.get("move", Vector2(0, -1))
		_player.call("set_camera_yaw", atan2(-move_dir.x, -move_dir.y))
		_player.call("set_autopilot", move_dir)
		## Hareketin başlaması için birkaç kare bekle.
		for i in 20:
			await physics_frame
		## Karakter hareket ederken çek (gövde hız yönüne dönmüş olmalı).
		var target: Vector3 = _player.global_position + Vector3(0, 1.15, 0)
		_cam.global_position = target + off
		_cam.look_at(target, Vector3.UP)
		for i in 6:
			await process_frame
		# headless modda frame_post_draw ASILIR -> yalnizca grafik modda cek
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			if img != null:
				img.save_png("%s/%s.png" % [_out, v["name"]])
				print("  ✓ %s.png" % v["name"])
	_player.call("set_autopilot", Vector2.ZERO)

	print("\n=== SONUÇ: %d/%d geçti ===\n" % [passed, passed + failed])
	quit(0 if failed == 0 else 1)


## Bir node altındaki TÜM mesh'lerin dünya sınırlarını ölçer (recursive).
func _measure_bounds(node: Node) -> Array:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for child in node.get_children():
		if child is MeshInstance3D:
			var m: Mesh = (child as MeshInstance3D).mesh
			if m != null:
				var bb: AABB = m.get_aabb()
				var xf: Transform3D = (child as MeshInstance3D).global_transform
				for cx in [bb.position.x, bb.position.x + bb.size.x]:
					for cy in [bb.position.y, bb.position.y + bb.size.y]:
						for cz in [bb.position.z, bb.position.z + bb.size.z]:
							var w: Vector3 = xf * Vector3(cx, cy, cz)
							mn = mn.min(w)
							mx = mx.max(w)
		var sub: Array = _measure_bounds(child)
		mn = mn.min(sub[0])
		mx = mx.max(sub[1])
	return [mn, mx]


## Alt node'lardaki "Hand" mesh'lerinin merkezlerini toplar.
func _collect_hands(node: Node, out: Array[Vector3]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and "Hand" in child.name:
			var mm: Mesh = (child as MeshInstance3D).mesh
			if mm != null:
				var bb3: AABB = mm.get_aabb()
				var hp: Vector3 = (child as MeshInstance3D).global_transform * \
					(bb3.position + bb3.size * 0.5)
				out.append(hp)
		_collect_hands(child, out)


## Yüz mesh'lerinin ortalama Z konumu → bakış yönü.
##
## Godot'ta karakterin ileri yönü -Z'dir. Yüz mesh'leri KARAKTERİN
## YEREL uzayında ölçülmelidir (global değil) — çünkü 180° yaw
## düzeltmesi global Z'yi tersine çevirir.
##
## Ham mesh'te yüz +Z'de (Blender'da öyle kuruldu). 180° yaw sonrası
## karakter yerel uzayında yüz hâlâ +Z'de ama dünya uzayında -Z'ye bakar.
## Bu yüzden: yerel ölçümde yüzün işareti, dünya ölçümde ters çevrilir.
func _face_points_forward(char_node: Node3D) -> bool:
	var face_nodes: Array[Node3D] = []
	_collect_by_name(char_node, ["Eye", "Nose", "Mouth"], face_nodes)
	if face_nodes.is_empty():
		return false
	## Karakterin YEREL uzayında ölç (global_transform yerine
	## transform kullan) — yaw düzeltmesinin etkisini görmez.
	var local_z: float = 0.0
	var count: int = 0
	for fn in face_nodes:
		var mm: Mesh = fn.mesh if fn is MeshInstance3D else null
		if mm == null:
			continue
		var bb: AABB = mm.get_aabb()
		var centre: Vector3 = bb.position + bb.size * 0.5
		local_z += fn.transform.basis.z.dot(centre)
		count += 1
	if count == 0:
		return false
	## Yerel uzayda yüz -Z tarafındaysa → dünyada da -Z'ye bakar.
	return (local_z / count) < 0.0


## İsim eşleşen node'ları toplar (recursive).
func _collect_by_name(node: Node, keys: Array, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D:
			for k in keys:
				if k in child.name:
					out.append(child)
					break
		_collect_by_name(child, keys, out)
