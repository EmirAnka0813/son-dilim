extends Node3D
##
## BÖLÜM 4 — SON YOKUŞ
## ============================================================================
## Yerleşim (X ekseni boyunca, Y yukarı):
##
##   x=0..14     Mahalle girişi (evler, sokak lambaları, bahçe ışıkları)
##   x=16..44    YOKUŞ — yükselen rampa (zemin Y=0'dan Y=5'e)
##   x=46..58    SON YOL — dik rampayı tırmanış, kaykaycılar
##   x=60..74    EVİN ÖNÜ — kapı, hedef, neon tabela
##
## ── YOKUŞ MEKANİĞİ ─────────────────────────────────────────────────────────
## Zemin yükselir → oyuncunun ivmesi değişir → KUTU DAHA ÇOK SARSILIR.
## Özellikle rampaya çıkarken (yavaşlama) ve inişte (hızlanma) krem kaçar.
##
## Fiziksel olarak: zemin bir dizi "basamak" yerine düz eğimli bir blok
## olarak yapılır (CharacterBody3D yokuş yürüyüşü destekler), ama görsel
## olarak basamaklar eklenir.
##
## ── KAYKAYCILAR ────────────────────────────────────────────────────────────
## Yokuştan aşağı kaykayla inen çocuklar — engel değil, KAÇILMASI GEREKEN
## hareketli objeler. Çarpışma → denge sarsar.
## ============================================================================

@export var total_length: float = 78.0
## Yokuşun başlangıç/bitiş X ve yükseklikleri.
@export var slope_start: float = 16.0
@export var slope_end: float = 44.0
@export var slope_top_y: float = 5.0

var _player: Player = null
var _skaters: Array[Dictionary] = []
var _model_cache: Dictionary = {}

var _road_mat: StandardMaterial3D
var _grass_mat: StandardMaterial3D
var _house_mats: Array[StandardMaterial3D] = []
var _window_lit: StandardMaterial3D
var _neon_pink: StandardMaterial3D
var _lamp_glow: StandardMaterial3D


func _ready() -> void:
	## Ortak ışık + atmosfer.
	LevelLighting.setup(self, "hill")
	_make_materials()
	_build_ground()
	_build_houses()
	_build_slope()
	_build_final_street()
	_build_skaters()
	_build_home()


func _make_materials() -> void:
	_road_mat = StandardMaterial3D.new()
	_road_mat.albedo_color = Color(0.13, 0.12, 0.16)
	_road_mat.roughness = 0.35
	_road_mat.metallic = 0.45

	_grass_mat = StandardMaterial3D.new()
	_grass_mat.albedo_color = Color(0.20, 0.34, 0.22)
	_grass_mat.roughness = 0.95

	_house_mats = []
	for c in [Color(0.48, 0.34, 0.30), Color(0.34, 0.40, 0.32),
			Color(0.40, 0.34, 0.46), Color(0.50, 0.42, 0.30)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.88
		_house_mats.append(m)

	_window_lit = StandardMaterial3D.new()
	_window_lit.albedo_color = Color(1.0, 0.86, 0.55)
	_window_lit.emission_enabled = true
	_window_lit.emission = Color(1.0, 0.78, 0.42)
	_window_lit.emission_energy_multiplier = 2.4

	_neon_pink = StandardMaterial3D.new()
	_neon_pink.albedo_color = Color(1.0, 0.32, 0.68)
	_neon_pink.emission_enabled = true
	_neon_pink.emission = Color(1.0, 0.2, 0.6)
	_neon_pink.emission_energy_multiplier = 3.2

	_lamp_glow = StandardMaterial3D.new()
	_lamp_glow.albedo_color = Color(1.0, 0.88, 0.62)
	_lamp_glow.emission_enabled = true
	_lamp_glow.emission = Color(1.0, 0.85, 0.55)
	_lamp_glow.emission_energy_multiplier = 3.0


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
## ZEMİN (düz bölüm + yokuş)
## ═══════════════════════════════════════════════════════════════════════════
func _build_ground() -> void:
	## Düz giriş bölümü.
	_add_sloped_box(Vector3(slope_start + 6.0, 0.4, 18), 0.0,
		Vector3(slope_start * 0.5 + 3.0, -0.2, 0), 0.0, _road_mat)
	## Yokuş: eğimli zemin (uzunluk = slope_end - slope_start).
	var run: float = slope_end - slope_start
	var rise: float = slope_top_y
	## Eğim açısı: atan(rise / run).
	var angle: float = atan(rise / run)
	## Yokuş bloğunun merkezi.
	var cx: float = (slope_start + slope_end) * 0.5
	var cy: float = rise * 0.5
	## Bloğu yatay eksende döndürüyoruz: yerel X ekseni eğime uyar.
	##
	## İŞARET DÜZELTMESİ: Rampa `+angle` ile eğilmelidir.
	##
	## ÖLÇÜLEN HATA: `-angle` kullanılıyordu → yokuş aşağı doğru iniyordu
	## ve oyuncu tepeye varamıyordu ("4. bölüm imkansız"). Bot 78 m
	## hedefe ulaşamıyor, x=68'de takılıp kalıyordu.
	##
	## `+angle` ile: blok X ekseninde yukarı doğru eğilir → x=16'da Y=0,
	## x=44'te Y=5. Oyuncu yokuşu tırmanır.
	var slope_box := _add_sloped_box(
		Vector3(sqrt(run * run + rise * rise), 0.4, 18), 0.0,
		Vector3(cx, cy - 0.2, 0), angle, _road_mat)
	slope_box.name = "SlopeRoad"

	## Son düz yol (tepe).
	_add_sloped_box(Vector3(total_length - slope_end + 6.0, 0.4, 18), 0.0,
		Vector3((slope_end + total_length) * 0.5 + 3.0, rise - 0.2, 0),
		0.0, _road_mat)

	## Kaldırımlar (yokuşla birlikte eğimli).
	## Kaldirimlar da yokuşla aynı yöne eğilir (+angle).
	for side in [-1.0, 1.0]:
		_add_sloped_box(Vector3(run, 0.34, 3.0), 0.0,
			Vector3(cx, cy + 0.05, side * 8.5), angle, _grass_mat)


## ═══════════════════════════════════════════════════════════════════════════
## EVLER (mahalle)
## ═══════════════════════════════════════════════════════════════════════════
func _build_houses() -> void:
	for i in 6:
		var hx: float = 4.0 + i * 11.0
		var h: float = 5.0 + randf() * 2.5
		var mat: StandardMaterial3D = _house_mats[i % _house_mats.size()]
		## Ev gövdesi.
		_add_box(Vector3(8.0, h, 7.0), Vector3(hx + 4.0, h * 0.5, -12.0),
			mat, true)
		## Çatı (kiremit).
		var roof := StandardMaterial3D.new()
		roof.albedo_color = Color(0.42, 0.18, 0.20)
		roof.roughness = 0.85
		_add_box(Vector3(8.6, 0.6, 7.6), Vector3(hx + 4.0, h + 0.3, -12.0),
			roof, false)
		## Kapı (yola dönük).
		var door := StandardMaterial3D.new()
		door.albedo_color = Color(0.34, 0.18, 0.12)
		door.roughness = 0.8
		_add_box(Vector3(1.2, 2.4, 0.2), Vector3(hx + 4.0, 1.2, -8.4),
			door, false)
		## Pencereler (sıcak ışık).
		for r in 2:
			for c in 2:
				_add_box(Vector3(1.2, 1.2, 0.16),
					Vector3(hx + 2.2 + c * 3.6, 1.8 + r * 2.4, -8.4),
					_window_lit if (r + c + i) % 3 != 0 else _grass_mat, false)
		## Bahçe ışığı.
		var pl := OmniLight3D.new()
		pl.light_color = Color(1.0, 0.82, 0.55)
		pl.light_energy = 1.8
		pl.omni_range = 9.0
		pl.position = Vector3(hx + 4.0, 2.4, -7.6)
		add_child(pl)
		## Sokak lambası (gerçek model varsa).
		var lamp: Node3D = _load_model("res://res/assets/models/street_lamp.glb")
		if lamp != null:
			lamp.position = Vector3(hx + 9.0, 0, 7.6)
			add_child(lamp)
			var ll := OmniLight3D.new()
			ll.light_color = Color(1.0, 0.85, 0.6)
			ll.light_energy = 2.0
			ll.omni_range = 12.0
			ll.position = Vector3(hx + 10.2, 5.2, 7.6)
			add_child(ll)


## ═══════════════════════════════════════════════════════════════════════════
## YOKUŞ DETAYLARI
## ═══════════════════════════════════════════════════════════════════════════
func _build_slope() -> void:
	var run: float = slope_end - slope_start
	var rise: float = slope_top_y
	var angle: float = atan(rise / run)

	## Kaldırım taşları (basamak hissi).
	for i in 14:
		var t: float = float(i) / 14.0
		var px: float = slope_start + t * run
		var py: float = t * rise
		for side in [-1.0, 1.0]:
			_add_box(Vector3(1.0, 0.16, 3.0),
				Vector3(px, py + 0.12, side * 8.5), _grass_mat, false)

	## Yokuş lambaları (eğime göre konumlanır).
	for i in 5:
		var t: float = float(i) / 5.0
		var px: float = slope_start + t * run
		var py: float = t * rise
		_add_box(Vector3(0.16, 4.2, 0.16), Vector3(px, py + 2.1, 7.6),
			_road_mat, true)
		_add_box(Vector3(0.55, 0.15, 0.35), Vector3(px, py + 4.25, 7.5),
			_lamp_glow, false)
		var pl := OmniLight3D.new()
		pl.light_color = Color(1.0, 0.85, 0.6)
		pl.light_energy = 2.2
		pl.omni_range = 12.0
		pl.position = Vector3(px, py + 4.0, 7.5)
		add_child(pl)

	## Eğim uyarı tabelası.
	_add_box(Vector3(0.2, 1.6, 1.0), Vector3(slope_start - 1.0, 0.9, 7.4),
		_neon_pink, false)


## ═══════════════════════════════════════════════════════════════════════════
## SON YOL (tepe)
## ═══════════════════════════════════════════════════════════════════════════
func _build_final_street() -> void:
	## Tepe düz yolunda kaldırım ve çit.
	for side in [-1.0, 1.0]:
		_add_box(Vector3(total_length - slope_end + 6.0, 0.34, 3.0),
			Vector3((slope_end + total_length) * 0.5 + 3.0,
				slope_top_y + 0.05, side * 8.5), _grass_mat, false)

	## Neon tabela sütunları (son yol ışıklandırma).
	for i in 4:
		var px: float = slope_end + 4.0 + i * 5.0
		_add_box(Vector3(0.14, 4.0, 0.14), Vector3(px, slope_top_y + 2.0, 7.4),
			_road_mat, true)
		_add_box(Vector3(0.4, 0.14, 0.4), Vector3(px, slope_top_y + 4.0, 7.4),
			_neon_pink, false)


## ═══════════════════════════════════════════════════════════════════════════
## KAYKAYCILAR
## ═══════════════════════════════════════════════════════════════════════════
func _build_skaters() -> void:
	## Yokuştan aşağı kaykayla inen çocuklar.
	for i in 4:
		var group := Node3D.new()
		add_child(group)
		var shirt := StandardMaterial3D.new()
		shirt.albedo_color = Color.from_hsv(randf(), 0.6, 0.7)
		shirt.roughness = 0.8
		_add_box_in(group, Vector3(0.42, 0.9, 0.32), Vector3(0, 0.68, 0), shirt)
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.9, 0.76, 0.66)
		skin.roughness = 0.7
		_add_box_in(group, Vector3(0.26, 0.28, 0.26), Vector3(0, 1.26, 0), skin)
		## Kaykay.
		var board := StandardMaterial3D.new()
		board.albedo_color = Color(0.30, 0.28, 0.34)
		board.roughness = 0.6
		_add_box_in(group, Vector3(0.24, 0.06, 1.1), Vector3(0, 0.10, 0), board)
		## Kollar (kaykay duruşu).
		for side in [-1.0, 1.0]:
			_add_box_in(group, Vector3(0.12, 0.6, 0.13),
				Vector3(side * 0.30, 0.68, 0), shirt)

		var start_x: float = slope_end - randf_range(2.0, 8.0)
		var start_y: float = slope_top_y * (1.0 - (start_x - slope_start) / run_ratio())
		group.position = Vector3(start_x, start_y + 0.2, randf_range(-3.0, 3.0))
		_skaters.append({
			"node": group,
			"speed": randf_range(4.0, 7.0),
			"phase": randf() * TAU,
		})


## Yokuş oranı (run/rise) yardımcısı.
func run_ratio() -> float:
	return maxf(1.0, slope_end - slope_start)


## ═══════════════════════════════════════════════════════════════════════════
## EV (final)
## ═══════════════════════════════════════════════════════════════════════════
func _build_home() -> void:
	var hx: float = total_length - 12.0
	## Ev gövdesi.
	_add_box(Vector3(11.0, 7.5, 9.0), Vector3(hx + 6.0, slope_top_y + 3.75, -11.0),
		_house_mats[0], true)
	## Çatı.
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.42, 0.18, 0.20)
	roof.roughness = 0.85
	_add_box(Vector3(11.6, 0.7, 9.6),
		Vector3(hx + 6.0, slope_top_y + 7.8, -11.0), roof, false)
	## Kapı (yola dönük).
	var door := StandardMaterial3D.new()
	door.albedo_color = Color(0.36, 0.20, 0.13)
	door.roughness = 0.78
	_add_box(Vector3(1.8, 3.2, 0.3),
		Vector3(hx + 6.0, slope_top_y + 1.6, -6.35), door, false)
	## Sundurma.
	_add_box(Vector3(2.6, 0.18, 1.3),
		Vector3(hx + 6.0, slope_top_y + 3.35, -5.9),
		roof, false)
	## Kapı ışığı.
	var dl := OmniLight3D.new()
	dl.light_color = Color(1.0, 0.84, 0.55)
	dl.light_energy = 3.0
	dl.omni_range = 12.0
	dl.position = Vector3(hx + 6.0, slope_top_y + 3.0, -5.2)
	add_child(dl)
	## Pencereler.
	for r in 2:
		for c in 3:
			_add_box(Vector3(1.3, 1.3, 0.18),
				Vector3(hx + 2.6 + c * 3.4, slope_top_y + 2.0 + r * 2.8, -6.35),
				_window_lit, false)
	## Bahçe ışıkları.
	for i in 4:
		var lx: float = hx + 1.5 + i * 3.0
		_add_box(Vector3(0.12, 3.0, 0.12),
			Vector3(lx, slope_top_y + 1.5, -5.6), _road_mat, true)
		_add_box(Vector3(0.4, 0.12, 0.4),
			Vector3(lx, slope_top_y + 3.0, -5.6), _lamp_glow, false)

	## ═══ "İYİ Kİ DOĞDUN DERİN!" NEON TABELASI ═══
	## Hikâyenin doruk noktası: eve gelince tabelanın yanar.
	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = Color(1.0, 0.85, 0.35)
	sign_mat.emission_enabled = true
	sign_mat.emission = Color(1.0, 0.82, 0.3)
	sign_mat.emission_energy_multiplier = 3.4
	_add_box(Vector3(7.0, 1.3, 0.24),
		Vector3(hx + 6.0, slope_top_y + 5.4, -6.3), sign_mat, false)
	## Tabela çerçevesi.
	_add_box(Vector3(7.4, 1.7, 0.3),
		Vector3(hx + 6.0, slope_top_y + 5.4, -6.4), _road_mat, false)
	## Tabelanın ışığı.
	var sl := OmniLight3D.new()
	sl.light_color = Color(1.0, 0.85, 0.4)
	sl.light_energy = 4.5
	sl.omni_range = 16.0
	sl.position = Vector3(hx + 6.0, slope_top_y + 5.2, -5.0)
	add_child(sl)

	## Hedef halkası (yolda).
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.2
	torus.outer_radius = 1.45
	ring.mesh = torus
	ring.material_override = _neon_pink
	ring.position = Vector3(hx + 1.0, slope_top_y + 0.12, 0)
	ring.rotation_degrees = Vector3(90, 0, 0)
	add_child(ring)


## ═══════════════════════════════════════════════════════════════════════════
## ANİMASYON + ETKİLEŞİM
## ═══════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	_animate_skaters(delta)


func _animate_skaters(delta: float) -> void:
	for s: Dictionary in _skaters:
		var node: Node3D = s["node"]
		var speed: float = s["speed"]
		node.position.x -= speed * delta
		## Yokuştan aşağı inerken Y de düşer.
		var t: float = clampf(
			(node.position.x - slope_start) / run_ratio(), 0.0, 1.0)
		node.position.y = slope_top_y * (1.0 - t) + 0.2
		## Kaykay duruşu.
		s["phase"] = float(s["phase"]) + delta * speed * 2.0
		for child in node.get_children():
			if child is MeshInstance3D:
				var m: MeshInstance3D = child
				if absf(m.position.x) > 0.2 and m.position.y < 1.2:
					m.rotation.x = sin(float(s["phase"])) * 0.5
		## Alt kısımdan çıkarsa başa sar.
		if node.position.x < slope_start - 6.0:
			node.position.x = slope_end - 1.0
			node.position.z = randf_range(-3.0, 3.0)


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	## Kaykaycı çarpması → denge sarsar, can gitmez.
	for s: Dictionary in _skaters:
		var node: Node3D = s["node"]
		var dx: float = absf(_player.global_position.x - node.position.x)
		var dz: float = absf(_player.global_position.z - node.position.z)
		if dx < 0.9 and dz < 0.8:
			if _player.global_position.y < node.position.y + 1.6:
				_player.balance.add_impulse(randf_range(-2.6, 2.6))
				_player.velocity.x += 2.0


## ═══════════════════════════════════════════════════════════════════════════
## YARDIMCI
## ═══════════════════════════════════════════════════════════════════════════
## Düz kutu ekle.
func _add_box(size: Vector3, pos: Vector3, mat: Material,
		with_collision: bool = true) -> MeshInstance3D:
	return _add_sloped_box(size, 0.0, pos, 0.0, mat, with_collision)


## Eğimli kutu ekle (yokuş zemini için).
## Eğimli zemin bloğu ekle.
##
## EKSEN DÜZELTMESİ (KRİTİK):
## Eski kod `mesh.rotation = Vector3(0.0, 0.0, angle)` idi — yani blok
## **Z ekseninde** (derinlik) döndürülüyordu. Oysa yokuş **X ekseninde**
## eğilmelidir (ileri yön +X, yukarı +Y).
##
## ÖLÇÜLEN SONUÇ: rot.x = 0.0000 rad → yokuş DÜZ kaldı → oyuncu tepeye
## çıkamıyordu → "4. bölüm imkansız" olarak raporlandı.
##
## Doğrusu: `rotation = Vector3(angle, 0.0, 0.0)` — X ekseninde döndür.
## Pozitif açı → +X tarafı YUKARI kalkar (tırmanış).
func _add_sloped_box(size: Vector3, _unused: float, pos: Vector3,
		angle: float, mat: Material, with_collision: bool = true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	## X ekseninde eğim (ileri yön +X, yukarı +Y).
	mesh.rotation = Vector3(angle, 0.0, 0.0)
	add_child(mesh)
	if with_collision:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		body.position = pos
		body.rotation = mesh.rotation
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
	return 3


func get_exit_position() -> Vector3:
	return Vector3(total_length - 10.0, slope_top_y + 1.5, 0.0)


func get_checkpoint_transforms() -> Array[Transform3D]:
	return [
		Transform3D(Basis(), Vector3(2, 0.1, 0)),
		Transform3D(Basis(), Vector3(14, 0.1, 0)),
		Transform3D(Basis(), Vector3(30, 2.4, 0)),
		Transform3D(Basis(), Vector3(46, 5.1, 0)),
		Transform3D(Basis(), Vector3(60, 5.1, 0)),
	]
