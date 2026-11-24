extends Node3D
##
## BÖLÜM 3 — TOPLU TAŞIMA KABUSU
## ============================================================================
## Yerleşim (X ekseni boyunca):
##
##   x=0..12     İstasyon girişi (turnikeler, yürüyen merdiven)
##   x=14..34    PLATFORM — kalabalık dalgası (26 kişi, yavaş akan)
##   x=36..58    TREN TÜNELİ — 2 vagon, hızlı hareket, dar alan
##   x=60..76    İstasyon çıkışı → Bölüm 4
##
## ── "KALABALIK KABUSU" MEKANİĞİ ───────────────────────────────────────────
## Buradaki asıl zorluk YAYALARDIR. Oyuncu kalabalığın arasından geçmeye
## çalışırken:
##   · Kalabalık oyuncunun önünde bir "duvar" oluşturur (yavaş akan bir kütle)
##   · Kalabalığa çarpmak kutuyu sarsar (ama can götürmez)
##   · Oyuncu kalabalığın arasından zıplayarak geçebilir
##
## ── TREN TÜNELİ ───────────────────────────────────────────────────────────
## Tünelde iki vagon ters yönde geçer. Oyuncu zamanlamayı bulmalı.
## Tünel dar (z ±3.2) → kaçış yolu dar → kutu sallanır.
##
## ── ENGELLER (çarpışma → denge sarsar, can gitmez) ────────────────────────
##   · Kalabalık (yayalar)
##   · Vagonlar
##   · Turnikeler
##   · Sütunlar
## ============================================================================

@export var total_length: float = 80.0
## Tünel başlangıç/bitiş.
@export var tunnel_start: float = 36.0
@export var tunnel_end: float = 58.0

var _player: Player = null
var _crowd: Array[Dictionary] = []
var _trains: Array[Dictionary] = []
var _model_cache: Dictionary = {}

var _tile_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _neon_cyan: StandardMaterial3D
var _neon_pink: StandardMaterial3D
var _glass_mat: StandardMaterial3D


func _ready() -> void:
	## Ortak ışık + atmosfer.
	LevelLighting.setup(self, "metro")
	_make_materials()
	_build_station()
	_build_platform()
	_build_crowd()
	_build_tunnel()
	_build_trains()
	_build_exit()


func _make_materials() -> void:
	_tile_mat = StandardMaterial3D.new()
	_tile_mat.albedo_color = Color(0.30, 0.29, 0.36)
	_tile_mat.roughness = 0.55

	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.36, 0.36, 0.46)
	_wall_mat.roughness = 0.7

	_neon_cyan = StandardMaterial3D.new()
	_neon_cyan.albedo_color = Color(0.28, 0.82, 1.0)
	_neon_cyan.emission_enabled = true
	_neon_cyan.emission = Color(0.2, 0.7, 1.0)
	_neon_cyan.emission_energy_multiplier = 2.8

	_neon_pink = StandardMaterial3D.new()
	_neon_pink.albedo_color = Color(1.0, 0.32, 0.68)
	_neon_pink.emission_enabled = true
	_neon_pink.emission = Color(1.0, 0.2, 0.6)
	_neon_pink.emission_energy_multiplier = 2.8

	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.16, 0.24, 0.32, 0.62)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.metallic = 0.6
	_glass_mat.roughness = 0.1


func _load_model(path: String) -> Node3D:
	## Cache PackedScene saklar (Node3D değil) — instance her seferinde yeniden
	## üretilir, çünkü bir Node3D'yi iki yere eklemek mümkün değildir.
	if _model_cache.has(path):
		var cached: PackedScene = _model_cache[path]
		if cached == null:
			return null
		return cached.instantiate()
	if not ResourceLoader.exists(path):
		_model_cache[path] = null
		return null
	var res: PackedScene = load(path)
	_model_cache[path] = res
	if res == null:
		return null
	return res.instantiate()

## ═══════════════════════════════════════════════════════════════════════════
## İSTASYON GİRİŞİ
## ═══════════════════════════════════════════════════════════════════════════
func _build_station() -> void:
	## Zemin.
	_add_box(Vector3(total_length, 0.4, 18), Vector3(total_length * 0.5, -0.2, 0),
		_tile_mat, true)

	## Arka duvar (yüzeye kaplı fayans + neon şerit).
	_add_box(Vector3(total_length, 10, 0.6),
		Vector3(total_length * 0.5, 5.0, -7.0), _wall_mat, true)
	for i in 12:
		_add_box(Vector3(5.0, 0.5, 0.2),
			Vector3(4.0 + i * 6.0, 6.4, -6.6),
			_neon_cyan if i % 2 == 0 else _neon_pink, false)

	## Tavan + kirişler + ışık şeritleri.
	_add_box(Vector3(total_length, 0.5, 15), Vector3(total_length * 0.5, 11.0, 0),
		_wall_mat, false)
	for i in 20:
		_add_box(Vector3(0.35, 0.6, 14.5),
			Vector3(2.0 + i * 4.0, 10.5, 0), _wall_mat, false)
	for i in 10:
		_add_box(Vector3(4.4, 0.12, 0.55),
			Vector3(4.0 + i * 8.0, 10.7, 0), _neon_cyan, false)

	## Sütunlar (platformun ritmi).
	for i in 11:
		var px: float = 4.0 + i * 7.0
		_add_box(Vector3(0.9, 11, 0.9), Vector3(px, 5.5, -5.0),
			_wall_mat, true)
		_add_box(Vector3(1.1, 0.3, 1.1), Vector3(px, 0.35, -5.0),
			_neon_cyan, false)

	## Turnikeler (giriş).
	for i in 4:
		var tx: float = 8.0 + i * 2.4
		_add_box(Vector3(0.5, 1.05, 1.8), Vector3(tx, 1.32, -2.6),
			_wall_mat, true)
		_add_box(Vector3(0.35, 0.12, 0.5), Vector3(tx, 1.92, -2.6),
			_neon_pink, false)

	## Yürüyen merdiven (arka planda).
	var esc := Node3D.new()
	for i in 14:
		var step := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(1.0, 0.28, 3.4)
		step.mesh = sb
		step.material_override = _wall_mat
		step.position = Vector3(0, i * 0.42, -3.4 + i * 0.05)
		esc.add_child(step)
	esc.position = Vector3(14.0, 0.2, -8.0)
	add_child(esc)


## ═══════════════════════════════════════════════════════════════════════════
## PLATFORM + KALABALIK
## ═══════════════════════════════════════════════════════════════════════════
func _build_platform() -> void:
	## Platform yükseltilmiş (zemin seviyesinden biraz yüksek = atlama).
	_add_box(Vector3(24, 0.7, 12), Vector3(24.0, 0.35, 0), _tile_mat, true)
	## Platform kenarı (sarı şerit).
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.95, 0.78, 0.18)
	yellow.emission_enabled = true
	yellow.emission = Color(0.9, 0.7, 0.12)
	yellow.emission_energy_multiplier = 0.6
	_add_box(Vector3(24, 0.04, 0.4), Vector3(24.0, 0.72, 5.8), yellow, false)


func _build_crowd() -> void:
	## 26 yaya — kalabalık dalgası.
	## Z davranışı: yavaş akan bir kütle. Oyuncu önüne geçmeye çalışırken
	## kalabalık da öne doğru iter (basınç).
	for i in 26:
		var group := Node3D.new()
		add_child(group)
		var shirt := StandardMaterial3D.new()
		shirt.albedo_color = Color.from_hsv(randf(), 0.38, 0.45)
		shirt.roughness = 0.85
		_add_box_in(group, Vector3(0.46, 0.98, 0.36), Vector3(0, 0.75, 0), shirt)
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.92, 0.78, 0.68)
		skin.roughness = 0.7
		_add_box_in(group, Vector3(0.28, 0.30, 0.28), Vector3(0, 1.38, 0), skin)
		for side in [-1.0, 1.0]:
			_add_box_in(group, Vector3(0.13, 0.64, 0.15),
				Vector3(side * 0.32, 0.75, 0), shirt)
		group.position = Vector3(randf_range(15.0, 33.0), 0.7,
			randf_range(-4.5, 4.5))
		_crowd.append({
			"node": group,
			"speed": randf_range(0.5, 1.4),
			"phase": randf() * TAU,
			"push": randf_range(0.2, 0.9),
		})


## ═══════════════════════════════════════════════════════════════════════════
## TREN TÜNELİ
## ═══════════════════════════════════════════════════════════════════════════
func _build_tunnel() -> void:
	var width: float = tunnel_end - tunnel_start
	var center: float = (tunnel_start + tunnel_end) * 0.5

	## Tünel duvarları (dar — kaçış yolu dar).
	for side in [-1.0, 1.0]:
		_add_box(Vector3(width, 9, 0.8),
			Vector3(center, 4.5, side * 3.6), _wall_mat, true)
		## Duvar neon şeridi.
		_add_box(Vector3(width, 0.3, 0.15),
			Vector3(center, 3.2, side * 3.15), _neon_pink, false)
	## Tünel tavanı.
	_add_box(Vector3(width, 0.6, 8.0), Vector3(center, 9.0, 0), _wall_mat, false)
	## Tünel zeminindeki uyarı ışıkları.
	for i in 8:
		_add_box(Vector3(0.6, 0.04, 0.6),
			Vector3(tunnel_start + 2.0 + i * 2.6, 0.22, 0),
			_neon_cyan, false)

	## Tünel giriş tabelası.
	_add_box(Vector3(0.3, 3.0, 5.0), Vector3(tunnel_start, 6.0, 0),
		_neon_pink, false)


func _build_trains() -> void:
	## 2 vagon — ters yönde, farklı hızda.
	var specs: Array[Dictionary] = [
		{"x": 42.0, "dir": 1, "speed": 13.0, "model": "minibus"},
		{"x": 52.0, "dir": -1, "speed": 16.0, "model": "minibus"},
	]
	for spec: Dictionary in specs:
		var group := Node3D.new()
		add_child(group)

		## Gerçek model varsa onu kullan.
		var model: Node3D = _load_model("res://res/assets/models/minibus.glb")
		if model != null:
			group.add_child(model)
		else:
			## Fallback: prosedürel vagon.
			var body := StandardMaterial3D.new()
			body.albedo_color = Color(0.30, 0.55, 0.42)
			body.metallic = 0.55
			body.roughness = 0.28
			_add_box_in(group, Vector3(11.0, 2.6, 2.6), Vector3(0, 1.8, 0), body)
			_add_box_in(group, Vector3(10.2, 1.1, 2.5), Vector3(0, 2.6, 0),
				_glass_mat)
			_add_box_in(group, Vector3(11.2, 0.2, 2.7), Vector3(0, 3.2, 0), body)
			var lamp := StandardMaterial3D.new()
			lamp.albedo_color = Color(1.0, 0.94, 0.72)
			lamp.emission_enabled = true
			lamp.emission = Color(1.0, 0.92, 0.6)
			lamp.emission_energy_multiplier = 3.0
			for s in [-1.0, 1.0]:
				_add_box_in(group, Vector3(0.14, 0.3, 0.5),
					Vector3(5.6, 2.0, s * 0.9), lamp)

		## Vagon iç ışığı.
		_add_box_in(group, Vector3(10.0, 0.1, 0.5), Vector3(0, 3.05, 0),
			_neon_cyan)

		group.position = Vector3(spec["x"], 0.2, 0)
		_trains.append({
			"node": group, "dir": spec["dir"], "speed": spec["speed"],
			"half_len": 5.6,
		})


## ═══════════════════════════════════════════════════════════════════════════
## ÇIKIŞ
## ═══════════════════════════════════════════════════════════════════════════
func _build_exit() -> void:
	var gate := StandardMaterial3D.new()
	gate.albedo_color = Color(1.0, 0.35, 0.70, 0.6)
	gate.emission_enabled = true
	gate.emission = Color(1.0, 0.2, 0.6)
	gate.emission_energy_multiplier = 3.2
	gate.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add_box(Vector3(0.3, 5.0, 6.0),
		Vector3(total_length - 2.0, 2.5, 0), gate, false)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.7)
	light.light_energy = 4.0
	light.omni_range = 16.0
	light.position = Vector3(total_length - 3.0, 2.5, 0)
	add_child(light)


## ═══════════════════════════════════════════════════════════════════════════
## ANİMASYON + ETKİLEŞİM
## ═══════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	_animate_crowd(delta)
	_animate_trains(delta)


func _animate_crowd(delta: float) -> void:
	for c: Dictionary in _crowd:
		var node: Node3D = c["node"]
		var speed: float = c["speed"]
		## Yürüyüş animasyonu.
		c["phase"] = float(c["phase"]) + delta * speed * 3.2
		var swing: float = sin(float(c["phase"])) * 0.45
		for child in node.get_children():
			if child is MeshInstance3D:
				var m: MeshInstance3D = child
				if absf(m.position.x) > 0.2 and m.position.y < 1.2:
					m.rotation.x = swing
		## Kalabalık YAVAŞ AKIYOR (+X). Oyuncu önüne geçmeye çalışırken
		## kalabalık da öne iter — basınç hissi.
		node.position.x += speed * delta
		if node.position.x > 34.0:
			node.position.x = 15.0


func _animate_trains(delta: float) -> void:
	for t: Dictionary in _trains:
		var node: Node3D = t["node"]
		node.position.x += float(t["dir"]) * float(t["speed"]) * delta
		if node.position.x > total_length + 8.0:
			node.position.x = tunnel_start - 8.0
		elif node.position.x < tunnel_start - 8.0:
			node.position.x = total_length + 8.0


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	## Kalabalık çarpması → kutu sarsılır (can gitmez).
	for c: Dictionary in _crowd:
		var node: Node3D = c["node"]
		var dx: float = absf(_player.global_position.x - node.position.x)
		var dz: float = absf(_player.global_position.z - node.position.z)
		if dx < 0.75 and dz < 0.7:
			if _player.global_position.y < 2.0:
				_player.balance.add_impulse(randf_range(-1.6, 1.6))
				## Kalabalık oyuncuyu iter.
				_player.velocity.x -= 1.2
	## Vagon çarpması → güçlü sarsıntı + geri itme.
	for t: Dictionary in _trains:
		var node: Node3D = t["node"]
		var dx: float = absf(_player.global_position.x - node.position.x)
		var dz: float = absf(_player.global_position.z - node.position.z)
		if dx < float(t["half_len"]) + 0.5 and dz < 1.8:
			if _player.global_position.y < 3.0:
				_player.balance.add_impulse(randf_range(-3.5, 3.5))
				_player.velocity.x -= float(t["dir"]) * 6.0


## ═══════════════════════════════════════════════════════════════════════════
## YARDIMCI
## ═══════════════════════════════════════════════════════════════════════════
func _add_box(size: Vector3, pos: Vector3, mat: Material,
		with_collision: bool = true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	add_child(mesh)
	if with_collision:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		body.position = pos
		add_child(body)
	return mesh


func _add_box_in(parent: Node3D, size: Vector3, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	return mesh


func get_level_index() -> int:
	return 2


func get_exit_position() -> Vector3:
	return Vector3(total_length - 2.0, 1.5, 0.0)


func get_checkpoint_transforms() -> Array[Transform3D]:
	return [
		Transform3D(Basis(), Vector3(2, 0.1, 0)),
		Transform3D(Basis(), Vector3(14, 0.8, 0)),
		Transform3D(Basis(), Vector3(34, 0.8, 0)),
		Transform3D(Basis(), Vector3(60, 0.2, 0)),
	]
