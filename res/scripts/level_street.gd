extends Node3D
##
## BÖLÜM 2 — TRAFİK CANAVARI
## ============================================================================
## Yerleşim (X ekseni boyunca):
##
##   x=0..14     Giriş (sokak başlangıcı, kaldırım)
##   x=16..34    AKIŞ TRAFİK — 8 araç, iki şerit, ters yönde geliyor
##   x=36..48    ISLAK ZEMİN BÖLGESİ — kaygan (krem çok daha kolay kaçar)
##   x=50..64    YAYA ALANI — kalabalık + sokak köpekleri
##   x=66..80    İNŞAAT ALANI — borular, koniler, bariyer
##   x=84        Son yokuş → Bölüm 3 kapısı
##
## ── ISLAK ZEMİN MEKANİĞİ ───────────────────────────────────────────────────
## Islak bölgede oyuncunun ivmesi **daha ani** olur (lastik tutmaz):
##   a_effective = a * 1.6
## Bu, denge sistemine daha büyük ivme bildirir → kutu daha çok sarsılır.
## Bölüm "kolay" olsun diye: bölgede kaza CEZASI yok, sadece zorlaşma.
##
## ── ARAÇ ÇARPMASI ──────────────────────────────────────────────────────────
## Araçlara çarpmak **pasta düşürmez** (çocuk dostu), sadece:
##   1. Kutuyu sarsar (denge sistemine ivme)
##   2. Oyuncu geri fırlatılır (itme)
##   3. Kısa bir "bump" sesi
## ============================================================================

@export var total_length: float = 92.0
## Islak zemin başlangıç/bitiş (X).
@export var wet_start: float = 36.0
@export var wet_end: float = 48.0
## Islak zeminde ivme çarpanı.
@export var wet_accel_multiplier: float = 1.6

## Hareketli araçlar: {node, yön, hız, yarı_uzunluk}
var _cars: Array[Dictionary] = []
## Yürüyen yayalar: {node, yön, hız, başlangıç_x}
var _pedestrians: Array[Dictionary] = []
## Bölgedeki tüm statik çarpışma gövdeleri (araç çarpması için).
var _player: Player = null

var _asphalt_mat: Material
var _wet_mat: StandardMaterial3D
var _sidewalk_mat: StandardMaterial3D
var _neon_mats: Array[StandardMaterial3D] = []
var _car_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	## Ortak ışık + atmosfer (LevelLighting) — sokak stratejisi.
	LevelLighting.setup(self, "street")
	_make_materials()
	## Modüler kiti kur — tüm ekleme işlemleri bundan sonra kit üzerinden.
	_kit = LevelKit.new(self, {
		"asphalt": _asphalt_mat,
		"sidewalk": _sidewalk_mat,
		"wet": _wet_mat,
	})
	_build_road()
	_build_wet_zone()
	_build_traffic()
	_build_pedestrians()
	_build_dogs()
	_build_construction()
	_build_exit_gate()
	_build_lamps()


func _make_materials() -> void:
	_asphalt_mat = StandardMaterial3D.new()
	_asphalt_mat.albedo_color = Color(0.09, 0.085, 0.11)
	_asphalt_mat.roughness = 0.28
	_asphalt_mat.metallic = 0.55
	## ISLAK ASFALT SHADER'ı — ıslak bölgeler ayna gibi, kuru bölgeler mat.
	## Fiziksel gerekçe: su mikro boşlukları doldurur → pürüzlülük çöker,
	## normal detayı düzleşir, yansıma güçlenir.
	var asphalt_tex: Texture2D = _texture("asphalt_albedo")
	var asphalt_nrm: Texture2D = _texture("asphalt_normal")
	var shader_path: String = "res://res/shaders/wet_asphalt.gdshader"
	if asphalt_tex != null and ResourceLoader.exists(shader_path):
		var shader: Shader = load(shader_path)
		if shader != null:
			var wet_mat := ShaderMaterial.new()
			wet_mat.shader = shader
			wet_mat.set_shader_parameter("albedo_tex", asphalt_tex)
			if asphalt_nrm != null:
				wet_mat.set_shader_parameter("normal_tex", asphalt_nrm)
			wet_mat.set_shader_parameter("wetness", 0.0)
			wet_mat.set_shader_parameter("rain_amount", 0.0)
			_wet_asphalt_mat = wet_mat
			_asphalt_mat = wet_mat
	elif asphalt_tex != null:
		## Fallback: shader yoksa standart PBR.
		_asphalt_mat.albedo_texture = asphalt_tex
		_asphalt_mat.uv1_scale = Vector3(10, 4, 1)
		if asphalt_nrm != null:
			_asphalt_mat.normal_enabled = true
			_asphalt_mat.normal_texture = asphalt_nrm
			_asphalt_mat.normal_scale = 0.7

	_wet_mat = StandardMaterial3D.new()
	_wet_mat.albedo_color = Color(0.06, 0.065, 0.10)
	_wet_mat.roughness = 0.04
	_wet_mat.metallic = 0.92
	_wet_mat.emission_enabled = true
	_wet_mat.emission = Color(0.10, 0.06, 0.18)
	_wet_mat.emission_energy_multiplier = 0.35

	_sidewalk_mat = StandardMaterial3D.new()
	_sidewalk_mat.albedo_color = Color(0.20, 0.19, 0.24)
	_sidewalk_mat.roughness = 0.85
	var pavement_tex: Texture2D = _texture("pavement_albedo")
	if pavement_tex != null:
		_sidewalk_mat.albedo_texture = pavement_tex
		_sidewalk_mat.uv1_scale = Vector3(8, 2, 1)
		var pavement_nrm: Texture2D = _texture("pavement_normal")
		if pavement_nrm != null:
			_sidewalk_mat.normal_enabled = true
			_sidewalk_mat.normal_texture = pavement_nrm
			_sidewalk_mat.normal_scale = 0.8

	for color in [Color(1.0, 0.30, 0.70), Color(0.30, 0.85, 1.0),
			Color(1.0, 0.82, 0.25), Color(0.48, 1.0, 0.54)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.6
		_neon_mats.append(m)

	for color in [Color(0.85, 0.55, 0.12), Color(0.15, 0.35, 0.62),
			Color(0.75, 0.15, 0.18), Color(0.20, 0.22, 0.26)]:
		var m2 := StandardMaterial3D.new()
		m2.albedo_color = color
		m2.metallic = 0.55
		m2.roughness = 0.28
		_car_mats.append(m2)


## ── DOKU ERİŞİMİ ───────────────────────────────────────────────────────────
## Global GameManager/Main üzerinden doku al (yoksa null → prosedürel kalır).
func _texture(key: String) -> Texture2D:
	var tree := get_tree()
	if tree == null:
		return null
	var main: Node = tree.root.get_node_or_null("Main")
	if main != null and main.has_method("texture"):
		return main.call("texture", key)
	return null


## ── GLB MODEL YÜKLEME ──────────────────────────────────────────────────────
## Blender'da üretilen gerçek modeller (tools/build_assets.py).
## Modeller yüklenemezse prosedürel fallback devreye girer — oyun bozulmaz.
var _model_cache: Dictionary = {}
var _use_models: bool = true
## Islak asfalt shader materyali (varsa).
var _wet_asphalt_mat: ShaderMaterial = null
## Modüler çevre kiti (game-code-architect: tek giriş noktası).
var _kit: LevelKit = null


## Bir GLB modelini yükle (yoksa null).
func _load_model(path: String) -> PackedScene:
	if _model_cache.has(path):
		return _model_cache[path]
	if not ResourceLoader.exists(path):
		_model_cache[path] = null
		return null
	var res: PackedScene = load(path)
	_model_cache[path] = res
	return res


## Model varsa onu, yoksa null döndür.
func _model(path: String) -> Node3D:
	if not _use_models:
		return null
	var packed: PackedScene = _load_model(path)
	if packed == null:
		return null
	var inst: Node3D = packed.instantiate()
	inst.name = path.get_file().get_basename()
	return inst


## ── YOL + KALDIRIM ─────────────────────────────────────────────────────────
func _build_road() -> void:
	## Ana asfalt.
	## ÖNEMLİ: with_collision = TRUE olmalı! Yanlışlıkla false verilirse
	## oyuncu zeminden düşer (sonsuza kadar y=-1200).
	_add_box(Vector3(total_length, 0.3, 14), Vector3(total_length * 0.5, -0.15, 0),
		_asphalt_mat, true)
	## Kaldırımlar (iki yanda, yükseltilmiş) — çarpışmalı (oyuncu üstünde yürür).
	for side in [-1.0, 1.0]:
		_add_box(Vector3(total_length, 0.34, 3.0),
			Vector3(total_length * 0.5, 0.17, side * 8.5), _sidewalk_mat, true)
		## Kaldırım kenarı (gri bant).
		var curb := StandardMaterial3D.new()
		curb.albedo_color = Color(0.42, 0.42, 0.48)
		curb.roughness = 0.8
		_add_box(Vector3(total_length, 0.08, 0.3),
			Vector3(total_length * 0.5, 0.36, side * 7.1), curb, false)

	## Sarı kesikli yol çizgileri.
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.92, 0.76, 0.18)
	line_mat.emission_enabled = true
	line_mat.emission = Color(0.7, 0.55, 0.1)
	line_mat.emission_energy_multiplier = 0.4
	var x: float = 4.0
	while x < total_length - 4.0:
		_add_box(Vector3(3.0, 0.02, 0.22), Vector3(x, 0.02, 0), line_mat, false)
		x += 6.0

	## Ayakkabı çizgisi (bastonlu ayakkabı detayı) — iki yanda.
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.30, 0.29, 0.36)
	base.roughness = 0.7
	for shoe_side in [-1.0, 1.0]:
		_add_box(Vector3(total_length, 0.16, 0.18),
			Vector3(total_length * 0.5, 0.16, shoe_side * 1.5), base, false)


## ── ISLAK ZEMİN ────────────────────────────────────────────────────────────
func _build_wet_zone() -> void:
	var width: float = wet_end - wet_start
	var center: float = (wet_start + wet_end) * 0.5
	## Islak asfalt üstte (parlak yansıma).
	## Shader varsa wetness/rain_amount uniform'ları ile sürülür.
	var wet_mesh: MeshInstance3D = _add_box(
		Vector3(width, 0.02, 13.4), Vector3(center, 0.03, 0), _wet_mat, false)
	if _wet_asphalt_mat != null:
		wet_mesh.material_override = _wet_asphalt_mat
	## Su birikintileri (parlak lekeler).
	for i in 6:
		var puddle := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.2 + randf() * 1.4
		cm.bottom_radius = 1.2 + randf() * 1.4
		cm.height = 0.02
		cm.radial_segments = 16
		puddle.mesh = cm
		puddle.material_override = _wet_mat
		puddle.position = Vector3(
			wet_start + randf() * width,
			0.05,
			randf_range(-5.5, 5.5))
		puddle.scale = Vector3(1.0, 1.0, randf_range(0.5, 0.9))
		add_child(puddle)

	## Uyarı tabelası.
	_add_box(Vector3(0.2, 1.6, 0.9), Vector3(wet_start - 1.0, 0.8, -7.2),
		_neon_mats[2], false)


## ── TRAFİK ─────────────────────────────────────────────────────────────────
func _build_traffic() -> void:
	## 8 araç, iki şeritte, ters yönlerde.
	var specs: Array[Dictionary] = [
		{"x": 20.0, "lane": -3.2, "dir": 1, "speed": 9.0, "type": "taxi"},
		{"x": 27.0, "lane": 3.2, "dir": -1, "speed": 8.0, "type": "sedan"},
		{"x": 31.0, "lane": -3.2, "dir": 1, "speed": 11.0, "type": "minibus"},
		{"x": 38.0, "lane": 3.2, "dir": -1, "speed": 9.5, "type": "taxi"},
		{"x": 44.0, "lane": -3.2, "dir": 1, "speed": 10.0, "type": "sedan"},
		{"x": 52.0, "lane": 3.2, "dir": -1, "speed": 8.5, "type": "minibus"},
		{"x": 58.0, "lane": -3.2, "dir": 1, "speed": 9.0, "type": "taxi"},
		{"x": 70.0, "lane": 3.2, "dir": -1, "speed": 10.5, "type": "sedan"},
	]
	for spec: Dictionary in specs:
		_make_car(spec)


func _make_car(spec: Dictionary) -> void:
	## Önce gerçek modeli dene (taxi / minibus / sedan).
	var model_path: String = ""
	match spec["type"]:
		"taxi": model_path = "res://res/assets/models/taxi.glb"
		"minibus": model_path = "res://res/assets/models/minibus.glb"
		_: model_path = "res://res/assets/models/sedan.glb"
	var model: Node3D = _model(model_path)
	if model != null:
		var group: Node3D = model
		add_child(group)
		## Model uzunluğu (çarışma yarı genişliği için).
		var mlen: float = 4.4 if spec["type"] != "minibus" else 6.0
		## Far ışığı.
		var hlight := SpotLight3D.new()
		hlight.light_color = Color(1.0, 0.93, 0.78)
		hlight.light_energy = 2.6
		hlight.spot_range = 13.0
		hlight.spot_angle = 30.0
		hlight.position = Vector3(mlen * 0.5, 1.2, 0)
		hlight.rotation_degrees = Vector3(-90, 0, 0)
		group.add_child(hlight)
		group.position = Vector3(spec["x"], 0, spec["lane"])
		_cars.append({
			"node": group, "dir": spec["dir"], "speed": spec["speed"],
			"half_len": mlen * 0.5, "lane": spec["lane"],
		})
		return

	## Fallback: prosedürel araç (model yoksa).
	var body_mat: StandardMaterial3D = _car_mats[randi() % _car_mats.size()]
	var group := Node3D.new()
	add_child(group)

	var is_minibus: bool = spec["type"] == "minibus"
	var is_taxi: bool = spec["type"] == "taxi"
	var length: float = 6.2 if is_minibus else 4.2
	var height: float = 3.1 if is_minibus else 2.5

	## Gövde.
	_add_box_in(group, Vector3(length, height * 0.55, 2.6),
		Vector3(0, height * 0.5, 0), body_mat)
	## Cam üst (kabin).
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.10, 0.16, 0.24, 0.72)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.7
	glass.roughness = 0.08
	_add_box_in(group, Vector3(length * 0.82, height * 0.42, 2.5),
		Vector3(-length * 0.05, height * 0.78, 0), glass)
	## Kaput.
	_add_box_in(group, Vector3(length * 0.22, height * 0.30, 2.4),
		Vector3(length * 0.42, height * 0.62, 0), body_mat)

	## Fenerler (ön).
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.95, 0.75)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.92, 0.65)
	lamp.emission_energy_multiplier = 3.0
	_add_box_in(group, Vector3(0.12, 0.22, 0.5),
		Vector3(length * 0.5, height * 0.45, -0.85), lamp)
	_add_box_in(group, Vector3(0.12, 0.22, 0.5),
		Vector3(length * 0.5, height * 0.45, 0.85), lamp)
	## Stop lambaları (arka).
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.9, 0.15, 0.12)
	tail.emission_enabled = true
	tail.emission = Color(1.0, 0.15, 0.1)
	tail.emission_energy_multiplier = 2.0
	_add_box_in(group, Vector3(0.1, 0.2, 0.4),
		Vector3(-length * 0.5, height * 0.45, -0.8), tail)
	_add_box_in(group, Vector3(0.1, 0.2, 0.4),
		Vector3(-length * 0.5, height * 0.45, 0.8), tail)

	## Tekerlekler.
	var tire := StandardMaterial3D.new()
	tire.albedo_color = Color(0.05, 0.05, 0.06)
	tire.roughness = 0.9
	for wx in [-length * 0.32, length * 0.32]:
		for wz in [-1.35, 1.35]:
			var wheel := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.52
			cm.bottom_radius = 0.52
			cm.height = 0.34
			cm.radial_segments = 12
			wheel.mesh = cm
			wheel.material_override = tire
			wheel.position = Vector3(wx, 0.52, wz)
			wheel.rotation.x = PI * 0.5
			group.add_child(wheel)

	## Taksi tabelası (tavan lambası).
	if is_taxi:
		_add_box_in(group, Vector3(1.0, 0.32, 0.5),
			Vector3(0, height * 1.02, 0), _neon_mats[2])

	## Far ışığı (yolda kuru ışık havuzu).
	var head_light := SpotLight3D.new()
	head_light.light_color = Color(1.0, 0.93, 0.78)
	head_light.light_energy = 3.0
	head_light.spot_range = 14.0
	head_light.spot_angle = 32.0
	head_light.position = Vector3(length * 0.5, height * 0.5, 0)
	head_light.rotation_degrees = Vector3(-90, 0, 0)
	group.add_child(head_light)

	group.position = Vector3(spec["x"], 0, spec["lane"])
	_cars.append({
		"node": group, "dir": spec["dir"], "speed": spec["speed"],
		"half_len": length * 0.5, "lane": spec["lane"],
	})


## ── YAYALAR ────────────────────────────────────────────────────────────────
func _build_pedestrians() -> void:
	for i in 14:
		var group := Node3D.new()
		add_child(group)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(randf(), 0.35, 0.42)
		mat.roughness = 0.85
		## Gövde.
		_add_box_in(group, Vector3(0.44, 0.95, 0.34), Vector3(0, 0.72, 0), mat)
		## Baş.
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.92, 0.78, 0.68)
		skin.roughness = 0.7
		_add_box_in(group, Vector3(0.26, 0.28, 0.26), Vector3(0, 1.34, 0), skin)
		## Kollar (sallanan).
		for side in [-1.0, 1.0]:
			_add_box_in(group, Vector3(0.12, 0.62, 0.14),
				Vector3(side * 0.30, 0.72, 0), mat)
		group.position = Vector3(randf_range(52, 76), 0.34,
			(randf() - 0.5) * 12.0)
		_pedestrians.append({
			"node": group,
			"dir": 1.0 if randf() > 0.5 else -1.0,
			"speed": randf_range(1.0, 2.2),
			"origin_z": group.position.z,
			"phase": randf() * TAU,
		})


## ── SOKAK KÖPEKLERİ ────────────────────────────────────────────────────────
func _build_dogs() -> void:
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.32, 0.25, 0.20)
	fur.roughness = 0.9
	for i in 3:
		var group := Node3D.new()
		add_child(group)
		## Gerçek köpek modeli varsa onu kullan.
		var dog_model: Node3D = _model("res://res/assets/models/dog.glb")
		if dog_model != null:
			group.add_child(dog_model)
			group.position = Vector3(56.0 + i * 7.0, 0.34,
				(randf() - 0.5) * 9.0)
			_pedestrians.append({
				"node": group, "dir": 0.0, "speed": 0.0,
				"origin_z": group.position.z, "phase": randf() * TAU,
			})
			continue
		_add_box_in(group, Vector3(0.82, 0.44, 0.32), Vector3(0, 0.42, 0), fur)
		_add_box_in(group, Vector3(0.26, 0.26, 0.24), Vector3(0.48, 0.52, 0), fur)
		## Kulaklar.
		for side in [-1.0, 1.0]:
			_add_box_in(group, Vector3(0.08, 0.16, 0.06),
				Vector3(0.46, 0.70, side * 0.08), fur)
		## Bacaklar.
		for lx in [-0.28, 0.28]:
			for lz in [-0.12, 0.12]:
				_add_box_in(group, Vector3(0.10, 0.40, 0.10),
					Vector3(lx, 0.20, lz), fur)
		## Kuyruk.
		_add_box_in(group, Vector3(0.28, 0.08, 0.08), Vector3(-0.52, 0.55, 0), fur)
		group.position = Vector3(56.0 + i * 7.0, 0.34,
			(randf() - 0.5) * 9.0)
		## Köpek engel olarak çarpışma üretmez — sadece görsel ve ses.
		_pedestrians.append({
			"node": group, "dir": 0.0, "speed": 0.0,
			"origin_z": group.position.z, "phase": randf() * TAU,
		})


## ── İNŞAAT ALANI ───────────────────────────────────────────────────────────
func _build_construction() -> void:
	var pipe_mat := StandardMaterial3D.new()
	pipe_mat.albedo_color = Color(0.42, 0.44, 0.48)
	pipe_mat.metallic = 0.8
	pipe_mat.roughness = 0.35
	## Borular (uzayda yatay).
	for i in 5:
		var pipe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.42
		cm.bottom_radius = 0.42
		cm.height = 12.0
		cm.radial_segments = 12
		pipe.mesh = cm
		pipe.material_override = pipe_mat
		pipe.position = Vector3(68.0 + i * 3.2, 0.78, randf_range(-3.0, 3.0))
		pipe.rotation.z = PI * 0.5
		add_child(pipe)

	## Koniler (turuncu, reflektif bantlı).
	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color(0.92, 0.38, 0.10)
	cone_mat.roughness = 0.8
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.95, 0.95, 0.85)
	band_mat.emission_enabled = true
	band_mat.emission = Color(0.7, 0.7, 0.6)
	band_mat.emission_energy_multiplier = 0.5
	for i in 8:
		var x: float = 67.0 + i * 2.6
		var cone := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.05
		cm2.bottom_radius = 0.32
		cm2.height = 0.9
		cm2.radial_segments = 10
		cone.mesh = cm2
		cone.material_override = cone_mat
		cone.position = Vector3(x, 0.79, 5.4)
		add_child(cone)
		_add_box(Vector3(0.44, 0.14, 0.44), Vector3(x, 0.92, 5.4), band_mat, false)

	## Bariyerler.
	var barrier_mat := StandardMaterial3D.new()
	barrier_mat.albedo_color = Color(0.90, 0.55, 0.10)
	barrier_mat.roughness = 0.85
	for i in 4:
		_add_box(Vector3(2.6, 0.55, 0.16),
			Vector3(68.0 + i * 5.4, 0.61, 6.6), barrier_mat, true)
		for lx in [-1.0, 1.0]:
			_add_box(Vector3(0.14, 0.7, 0.14),
				Vector3(68.0 + i * 5.4 + lx, 0.35, 6.6),
				barrier_mat, true)


## ── SOKAK LAMBALARI + NEON TABELA ──────────────────────────────────────────
func _build_lamps() -> void:
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.14, 0.14, 0.17)
	post_mat.metallic = 0.6
	post_mat.roughness = 0.5
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.88, 0.62)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.85, 0.55)
	glow.emission_energy_multiplier = 3.2

	for i in 8:
		var x: float = 6.0 + i * 11.0
		var side: float = -1.0 if i % 2 == 0 else 1.0
		## Gerçek lamba modeli varsa onu kullan.
		var lamp_model: Node3D = _model("res://res/assets/models/street_lamp.glb")
		if lamp_model != null:
			lamp_model.position = Vector3(x, 0, side * 7.6)
			add_child(lamp_model)
			var ll := OmniLight3D.new()
			ll.light_color = Color(1.0, 0.85, 0.6)
			ll.light_energy = 2.2
			ll.omni_range = 13.0
			ll.position = Vector3(x + 1.2, 5.2, side * 7.6)
			add_child(ll)
			continue
		_add_box(Vector3(0.16, 5.4, 0.16), Vector3(x, 2.7, side * 7.6), post_mat, true)
		_add_box(Vector3(0.7, 0.16, 0.4), Vector3(x, 5.45, side * 7.4), glow, false)
		## Işık huzmesi (additive koni).
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 2.4
		cm.height = 5.0
		cm.radial_segments = 12
		cone.mesh = cm
		var shaft := StandardMaterial3D.new()
		shaft.albedo_color = Color(1.0, 0.86, 0.60, 0.09)
		shaft.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shaft.emission_enabled = true
		shaft.emission = Color(1.0, 0.85, 0.55)
		shaft.emission_energy_multiplier = 0.5
		shaft.cull_mode = BaseMaterial3D.CULL_DISABLED
		cone.material_override = shaft
		cone.position = Vector3(x, 2.9, side * 7.4)
		add_child(cone)

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.6)
		light.light_energy = 2.4
		light.omni_range = 13.0
		light.position = Vector3(x, 5.2, side * 7.4)
		add_child(light)

	## BİNA CEPHANELERİ: gerçek Blender modeli (varsa).
	var building_model: Node3D = _model("res://res/assets/models/buildings.glb")
	if building_model != null:
		## Cephe dokusunu modelin gövde mesh'ine uygula.
		var facade_tex: Texture2D = _texture("facade_albedo")
		if facade_tex != null and building_model is Node3D:
			for child in building_model.get_children():
				if child is MeshInstance3D:
					var mat: StandardMaterial3D = StandardMaterial3D.new()
					mat.albedo_texture = facade_tex
					mat.uv1_scale = Vector3(2, 2, 1)
					mat.roughness = 0.88
					(child as MeshInstance3D).material_override = mat
		for i in 7:
			var bmodel: Node3D = building_model.duplicate()
			bmodel.position = Vector3(8.0 + i * 13.0, 0, -13.5)
			bmodel.scale = Vector3(1.0, 0.85 + (i % 3) * 0.28, 1.0)
			add_child(bmodel)
			## Cephe çarpışma duvarı (oyuncu içeri giremesin).
			_add_box(Vector3(10.0, 14.0, 1.0),
				Vector3(8.0 + i * 13.0 + 5.0, 7.0, -13.5), _sidewalk_mat, true)

	## Neon tabelalar (bina cephesinde).
	for i in 6:
		var x: float = 10.0 + i * 14.0
		var neon: StandardMaterial3D = _neon_mats[i % _neon_mats.size()]
		_add_box(Vector3(4.2, 0.9, 0.18), Vector3(x, 4.6, -11.4), neon, false)
		## Arkasında kutu.
		_add_box(Vector3(4.6, 1.3, 0.3), Vector3(x, 4.6, -11.6),
			_sidewalk_mat, true)
		var light2 := OmniLight3D.new()
		light2.light_color = neon.emission
		light2.light_energy = 2.0
		light2.omni_range = 10.0
		light2.position = Vector3(x, 4.4, -10.6)
		add_child(light2)


## ── BÖLÜM ÇIKIŞ KAPISI ─────────────────────────────────────────────────────
func _build_exit_gate() -> void:
	var gate_mat := StandardMaterial3D.new()
	gate_mat.albedo_color = Color(1.0, 0.35, 0.70, 0.6)
	gate_mat.emission_enabled = true
	gate_mat.emission = Color(1.0, 0.2, 0.6)
	gate_mat.emission_energy_multiplier = 3.2
	gate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add_box(Vector3(0.3, 5.0, 6.0), Vector3(total_length - 2.0, 2.5, 0), gate_mat, false)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.7)
	light.light_energy = 4.0
	light.omni_range = 16.0
	light.position = Vector3(total_length - 3.0, 2.5, 0)
	add_child(light)


## ═══════════════════════════════════════════════════════════════════════════
## ANİMASYON
## ═══════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	## Islak asfalt shader uniform'larini güncelle.
	## Player ıslak bölgeye girdiğinde wetness artar (yumuşak geçiş).
	if _wet_asphalt_mat != null:
		var wet_target: float = 0.0
		if _player != null:
			var px: float = _player.global_position.x
			if px >= wet_start and px <= wet_end:
				## Girişte 0.35, ortada 1.0 (en ıslak), çıkışta 0.35.
				var mid: float = (wet_start + wet_end) * 0.5
				var half: float = maxf(1.0, (wet_end - wet_start) * 0.5)
				var dist: float = absf(px - mid) / half
				wet_target = lerpf(1.0, 0.35, clampf(dist, 0.0, 1.0))
		var current: float = float(_wet_asphalt_mat.get_shader_parameter("wetness")) \
			if _wet_asphalt_mat.get_shader_parameter("wetness") != null else 0.0
		## Yumuşak geçiş (yumuşak sınır = pürüzsüz hareket).
		_wet_asphalt_mat.set_shader_parameter("wetness",
			lerpf(current, wet_target, 4.0 * delta))
		## Her zaman yağmur yağıyor (akşam yağmuru).
		_wet_asphalt_mat.set_shader_parameter("rain_amount", 0.75)
		_wet_asphalt_mat.set_shader_parameter("rain_speed", 1.6)
	_animate_cars(delta)
	_animate_pedestrians(delta)


func _animate_cars(delta: float) -> void:
	for car: Dictionary in _cars:
		var node: Node3D = car["node"]
		var dir: float = car["dir"]
		node.position.x += dir * car["speed"] * delta
		## Sahne sınırlarında geri dön.
		if node.position.x > total_length + 6.0:
			node.position.x = -6.0
		elif node.position.x < -6.0:
			node.position.x = total_length + 6.0
		## Zemin izleri (görsel).
		node.rotation.y = 0.0 if dir > 0.0 else PI


func _animate_pedestrians(delta: float) -> void:
	for ped: Dictionary in _pedestrians:
		var node: Node3D = ped["node"]
		var speed: float = ped["speed"]
		if speed <= 0.01:
			continue
		## Yürüyüş animasyonu: kollar sallanır (basit Z dönüşü).
		ped["phase"] = float(ped["phase"]) + delta * speed * 3.0
		var swing: float = sin(float(ped["phase"])) * 0.5
		for child in node.get_children():
			if child is MeshInstance3D:
				var m: MeshInstance3D = child
				## Kollar (ince, düşük konumlu) sallanır.
				if absf(m.position.x) > 0.2 and m.position.y < 1.0:
					m.rotation.x = swing
		## Yön değiştirme (kaldırım sınırında).
		node.position.x += float(ped["dir"]) * speed * delta
		if node.position.x > 78.0:
			node.position.x = 50.0
		elif node.position.x < 50.0:
			node.position.x = 78.0


## ═══════════════════════════════════════════════════════════════════════════
## OYUNCU ETKİLEŞİMİ
## ═══════════════════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	if _player == null:
		return
	## Islak bölgede ivme daha sert → kutuyu daha çok sarsar.
	var in_wet: bool = (_player.global_position.x >= wet_start
		and _player.global_position.x <= wet_end)
	if in_wet and _player.balance:
		## Etkiyi büyütmek için ek bir sarsıntı üretiyoruz.
		_player.balance.add_impulse(
			sin(Time.get_ticks_msec() * 0.003) * 0.02)
	## Araç çarpması → sarsıntı + geri itme (can gitmez).
	for car: Dictionary in _cars:
		var node: Node3D = car["node"]
		var dx: float = absf(_player.global_position.x - node.position.x)
		var dz: float = absf(_player.global_position.z - node.position.z)
		var half_len: float = car["half_len"]
		if dx < half_len + 0.5 and dz < 1.6:
			## Oyuncu aracın üstünden zıplıyorsa çarpışma yok.
			if _player.global_position.y > 2.2:
				continue
			_player.balance.add_impulse(randf_range(-2.2, 2.2))
			_player.velocity.x -= float(car["dir"]) * 4.0
			## Anlık gürültü (bump).
			_player.balance.balance_changed.emit(
				_player.balance.angle, _player.balance.slip)


## ═══════════════════════════════════════════════════════════════════════════
## YARDIMCI
## ═══════════════════════════════════════════════════════════════════════════
## Çok sayıda aynı kutuyu TEK MultiMesh olarak ekler (1 çizim çağrısı).
## game-performance-optimizer: "Repeated props instanced" kuralı.
func _add_multimesh_boxes(transforms: Array[Transform3D], size: Vector3,
		material: Material) -> MultiMeshInstance3D:
	if transforms.is_empty():
		return null
	var box := BoxMesh.new()
	box.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	mm.use_colors = false
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
	return mmi


## Kutu ekle (çarpışma isteğe bağlı).
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


## Grup içine kutu ekle (araç parçaları için).
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


## Bu bölümün indeksi (0=ofis, 1=sokak) — testler ve yükleme için.
func get_level_index() -> int:
	return 1


## Bölüm çıkışının konumu.
func get_exit_position() -> Vector3:
	return Vector3(total_length - 2.0, 1.5, 0.0)


## Checkpoint'ler.
func get_checkpoint_transforms() -> Array[Transform3D]:
	return [
		Transform3D(Basis(), Vector3(2, 0.1, 0)),
		Transform3D(Basis(), Vector3(34, 0.1, 0)),
		Transform3D(Basis(), Vector3(50, 0.4, 0)),
		Transform3D(Basis(), Vector3(66, 0.1, 0)),
	]
