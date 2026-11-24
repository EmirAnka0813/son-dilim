extends Node3D
##
## BÖLÜM 1 — OFİSTEN KAÇIŞ
## ============================================================================
## Yerleşim (X ekseni boyunca, oyuncu +X yönünde ilerler):
##
##   x=0        Ofis başlangıcı (giriş)
##   x=6..34    Masa sıraları (çarpışma engelleri)
##   x=38       Ofis kapısı
##   x=40..52   ASANSÖR BOŞLUĞU (3 atlama platformu — zıplayarak geç)
##   x=56       Plaza çıkışı → Bölüm 2
##
## Checkpoint'ler: x=4 (giriş), x=36 (asansör önü), x=54 (plaza)
## ============================================================================

@export var asansor_start: float = 40.0
@export var asansor_end: float = 52.0

## Masa malzemesi.
var _masa_mat: StandardMaterial3D
var _ekran_mat: StandardMaterial3D
var _zemin_mat: StandardMaterial3D
var _tavan_isik_mat: StandardMaterial3D


## Modüler çevre kiti (game-code-architect: tek giriş noktası).
var _kit: LevelKit = null


func _ready() -> void:
	## Ortak ışık + atmosfer (LevelLighting) — her bölüm aynı stratejiyi kullanır.
	LevelLighting.setup(self, "interior")
	_make_materials()
	_kit = LevelKit.new(self, {
		"floor": _zemin_mat,
		"masa": _masa_mat,
		"ekran": _ekran_mat,
		"tavan_isik": _tavan_isik_mat,
	})
	_build_ceiling_lights()
	_build_floor()
	_build_walls()
	_build_desks()
	_build_asansor()
	_build_plaza_exit()


## ── TAVAN FLORESANLARI ─────────────────────────────────────────────────────
## Ofis 60m uzunlukta — tek ışık yetmez. Tavan boyunca 12 şerit floresan:
##   · Her şerit = emissive mesh (görünen panel) + OmniLight (gerçek aydınlatma)
##   · Işıklar 8m arayla → homojen aydınlatma, gölge yumuşak
## environment-world-builder: "Her ışığın amacı var" → tavan aydınlatma.
func _build_ceiling_lights() -> void:
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.92, 0.95, 1.0)
	panel_mat.emission_enabled = true
	panel_mat.emission = Color(0.85, 0.92, 1.0)
	panel_mat.emission_energy_multiplier = 2.6
	## Asıl aydınlatma ışığının rengi (soğuk floresan).
	var light_color := Color(0.84, 0.90, 1.0)

	for i in 13:
		var lx: float = 2.0 + i * 4.6
		## Tavan paneli (görünen) — kit üzerinden, çarpışma yok.
		_kit.add_box(Vector3(3.2, 0.10, 0.85), Vector3(lx, 4.6, 0),
			panel_mat, false)
		## Gerçek ışık.
		var lamp := OmniLight3D.new()
		lamp.light_color = light_color
		lamp.light_energy = 2.4
		lamp.omni_range = 11.0
		lamp.omni_attenuation = 1.2
		lamp.shadow_enabled = false
		lamp.position = Vector3(lx, 4.3, 0)
		add_child(lamp)

	## Asansör boşluğu için ayrı ışık (vurgu).
	var shaft := OmniLight3D.new()
	shaft.light_color = Color(0.70, 0.86, 1.0)
	shaft.light_energy = 3.2
	shaft.omni_range = 16.0
	shaft.position = Vector3(46, 4.0, 0)
	add_child(shaft)

	## Plaza çıkışı için sıcak ışık (dışarı geçiş hissi).
	var exit_light := OmniLight3D.new()
	exit_light.light_color = Color(1.0, 0.86, 0.64)
	exit_light.light_energy = 3.4
	exit_light.omni_range = 14.0
	exit_light.position = Vector3(54, 3.0, 0)
	add_child(exit_light)


func _make_materials() -> void:
	_masa_mat = StandardMaterial3D.new()
	_masa_mat.albedo_color = Color(0.28, 0.26, 0.34)
	_masa_mat.roughness = 0.55

	_ekran_mat = StandardMaterial3D.new()
	_ekran_mat.albedo_color = Color(0.05, 0.35, 0.55)
	_ekran_mat.emission_enabled = true
	_ekran_mat.emission = Color(0.1, 0.55, 0.9)
	_ekran_mat.emission_energy_multiplier = 1.4

	_zemin_mat = StandardMaterial3D.new()
	_zemin_mat.albedo_color = Color(0.16, 0.15, 0.2)
	_zemin_mat.roughness = 0.35
	_zemin_mat.metallic = 0.3

	_tavan_isik_mat = StandardMaterial3D.new()
	_tavan_isik_mat.albedo_color = Color(0.95, 0.95, 0.85)
	_tavan_isik_mat.emission_enabled = true
	_tavan_isik_mat.emission = Color(1.0, 0.95, 0.8)
	_tavan_isik_mat.emission_energy_multiplier = 2.2


## ── ZEMİN ───────────────────────────────────────────────────────────────────
func _build_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(70, 0.4, 16)
	floor_mesh.mesh = box
	floor_mesh.material_override = _zemin_mat
	floor_mesh.position = Vector3(28, -0.2, 0)
	add_child(floor_mesh)

	## Statik gövde (çarpışma).
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(70, 0.4, 16)
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(28, -0.2, 0)
	add_child(body)


## ── DUVARLAR (koridor) ─────────────────────────────────────────────────────
func _build_walls() -> void:
	for side in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(70, 7, 0.5)
		wall.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.21, 0.3)
		mat.roughness = 0.7
		wall.material_override = mat
		wall.position = Vector3(28, 3.5, side * 8.0)
		add_child(wall)

		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(70, 7, 0.5)
		col.shape = shape
		body.add_child(col)
		body.position = Vector3(28, 3.5, side * 8.0)
		add_child(body)

	## Cam cephe (ofis camı) — arka duvarda.
	for i in 12:
		var pane := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(3.6, 6.0, 0.12)
		pane.mesh = pb
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.35, 0.55, 0.72, 0.42)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.metallic = 0.4
		pm.roughness = 0.1
		pane.material_override = pm
		pane.position = Vector3(4 + i * 4.4, 3.2, -7.7)
		add_child(pane)

	## Tavan spot lambaları.
	for i in 10:
		var lamp := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(1.4, 0.12, 0.5)
		lamp.mesh = lb
		lamp.material_override = _tavan_isik_mat
		lamp.position = Vector3(3 + i * 6.0, 6.6, -4.0)
		add_child(lamp)

	var light := OmniLight3D.new()
	light.light_color = Color(0.85, 0.92, 1.0)
	light.light_energy = 1.6
	light.omni_range = 22.0
	light.position = Vector3(14, 5.5, 0)
	add_child(light)

	var light2 := OmniLight3D.new()
	light2.light_color = Color(0.85, 0.92, 1.0)
	light2.light_energy = 1.4
	light2.omni_range = 22.0
	light2.position = Vector3(32, 5.5, 0)
	add_child(light2)


## ── MASALAR (engeller) ─────────────────────────────────────────────────────
func _build_desks() -> void:
	for i in 7:
		var x: float = 8.0 + i * 4.0
		for side in [-1.0, 1.0]:
			var z: float = side * 4.5
			## Masa tablası.
			var desk := MeshInstance3D.new()
			var db := BoxMesh.new()
			db.size = Vector3(2.6, 0.1, 1.4)
			desk.mesh = db
			desk.material_override = _masa_mat
			desk.position = Vector3(x, 0.78, z)
			add_child(desk)

			## Bacaklar.
			for lx in [-1.1, 1.1]:
				var leg := MeshInstance3D.new()
				var lb := BoxMesh.new()
				lb.size = Vector3(0.1, 0.75, 1.2)
				leg.mesh = lb
				leg.material_override = _masa_mat
				leg.position = Vector3(x + lx, 0.37, z)
				add_child(leg)

			## Monitör.
			var mon := MeshInstance3D.new()
			var mb := BoxMesh.new()
			mb.size = Vector3(1.1, 0.7, 0.08)
			mon.mesh = mb
			mon.material_override = _ekran_mat
			mon.position = Vector3(x, 1.25, z + side * 0.3)
			mon.rotation.y = PI if side > 0 else 0.0
			add_child(mon)

			## Çarpışma gövdesi (masa engeli).
			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(2.6, 1.6, 1.4)
			col.shape = shape
			body.add_child(col)
			body.position = Vector3(x, 0.8, z)
			add_child(body)


## ── ASANSÖR BOŞLUĞU (zıplama platformları) ──────────────────────────────────
func _build_asansor() -> void:
	## Boşluk: x=40..52 arasında zemin yok.
	## 3 atlama platformu — yükseldikçe.
	var platforms: Array[Vector3] = [
		Vector3(41.5, 0.9, 0.0),
		Vector3(45.0, 1.7, -1.2),
		Vector3(48.5, 2.5, 0.4),
	]
	for p: Vector3 in platforms:
		var plat := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(3.0, 0.35, 3.0)
		plat.mesh = pb
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.42, 0.40, 0.52)
		pm.roughness = 0.6
		plat.material_override = pm
		plat.position = p
		add_child(plat)

		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(3.0, 0.35, 3.0)
		col.shape = shape
		body.add_child(col)
		body.position = p
		add_child(body)

		## Platform kenarında sarı uyarı şeridi.
		var stripe := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(3.05, 0.06, 0.3)
		stripe.mesh = sb
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.95, 0.78, 0.15)
		sm.emission_enabled = true
		sm.emission = Color(0.9, 0.7, 0.1)
		sm.emission_energy_multiplier = 0.8
		stripe.material_override = sm
		stripe.position = p + Vector3(0, 0.2, 1.35)
		add_child(stripe)

	## Asansör kuyusu duvarı (boşluğun iki yanı).
	for side in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(12, 9, 0.4)
		wall.mesh = wb
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.18, 0.17, 0.25)
		wall.material_override = wm
		wall.position = Vector3(46, 4.5, side * 5.0)
		add_child(wall)

		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(12, 9, 0.4)
		col.shape = shape
		body.add_child(col)
		body.position = Vector3(46, 4.5, side * 5.0)
		add_child(body)


## ── PLAZA ÇIKIŞI (bölüm 2 kapısı) ───────────────────────────────────────────
func _build_plaza_exit() -> void:
	## Bölüm sonu kapısı — parlayan hedef.
	var gate := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(0.3, 4.0, 5.0)
	gate.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(1.0, 0.35, 0.7)
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.2, 0.6)
	gm.emission_energy_multiplier = 3.0
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color.a = 0.55
	gate.material_override = gm
	gate.position = Vector3(60, 2.0, 0)
	add_child(gate)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.7)
	light.light_energy = 3.0
	light.omni_range = 14.0
	light.position = Vector3(59, 2.5, 0)
	add_child(light)

	## Zemin devamı (asansörden sonra).
	var floor_mesh := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(10, 0.4, 16)
	floor_mesh.mesh = fb
	floor_mesh.material_override = _zemin_mat
	floor_mesh.position = Vector3(57, -0.2, 0)
	add_child(floor_mesh)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, 0.4, 16)
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(57, -0.2, 0)
	add_child(body)


## Bu bölümün indeksi (0=ofis) — testler ve yükleme için.
func get_level_index() -> int:
	return 0


## Bölüm çıkışının konumu (Main.tscn buraya Area3D ekler).
func get_exit_position() -> Vector3:
	return Vector3(60.0, 1.5, 0.0)


## ── CHECKPOINT'LER (GameManager tarafından okunur) ───────────────────────────
func get_checkpoint_transforms() -> Array[Transform3D]:
	return [
		Transform3D(Basis(), Vector3(2, 0.1, 0)),
		Transform3D(Basis(), Vector3(37, 0.1, 0)),
		Transform3D(Basis(), Vector3(54, 2.9, 0.4)),
	]
