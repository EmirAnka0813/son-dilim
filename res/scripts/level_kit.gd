class_name LevelKit
extends RefCounted
##
## MODÜLER ÇEVRE KİTİ (Modular Environment Kit)
## ============================================================================
## environment-world-builder + game-code-architect prensipleri:
##
##   · Tüm ölçüler METRE cinsinden ve tek bir ızgara (1m) üzerinde.
##   · Her parça paylaşılan malzeme seti kullanır → BATCHING mümkün.
##   · Tek giriş noktası: `add_box()` — tüm level scriptleri bunu kullanır.
##   · Çarpışma isteğe bağlı: görsel mesh, fizik gerektirmiyorsa çarpışma yok.
##
## ÖLÇÜ SABİTLERİ (metre cinsinden — environment-world-builder "Metre Kuralı"):
##
##   Kapı yüksekliği     2.0     Koridor genişliği   2.0-2.5
##   Tavan yüksekliği    3.0     Kaldırım genişliği  2.2
##   Yol şeridi          3.2     Bina katı           3.2
##   Karakter boyu      1.80     Göz yüksekliği      1.65
##
## KULLANIM:
##   var kit := LevelKit.new()
##   kit.setup(self, materials)
##   kit.add_box(Vector3(8, 3, 0.4), Vector3(10, 1.5, -6), kit.wall)
## ============================================================================

## Izgara adımı (metre).
const GRID: float = 1.0

## Sahne (node'lar buraya eklenir).
var host: Node3D = null
## Malzeme seti.
var mats: Dictionary = {}


func _init(host_node: Node3D, materials: Dictionary = {}) -> void:
	host = host_node
	mats = materials


## Malzeme al (yoksa null).
func mat(key: String) -> Material:
	return mats.get(key, null)


## Izgaraya yuvarla (yarım metre adım).
static func snap(v: Vector3) -> Vector3:
	return Vector3(
		snappedf(v.x, 0.5),
		snappedf(v.y, 0.5),
		snappedf(v.z, 0.5))


## Kutu ekle. Çarpışma isteğe bağlı.
func add_box(size: Vector3, pos: Vector3, material: Material,
		with_collision: bool = true, snap_to_grid: bool = false) -> MeshInstance3D:
	if host == null:
		return null
	var p: Vector3 = snap(pos) if snap_to_grid else pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = p
	host.add_child(mesh)
	if with_collision:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		body.position = p
		host.add_child(body)
	return mesh


## Eğimli kutu ekle (yokuş zemini).
func add_sloped_box(size: Vector3, pos: Vector3, angle_z: float,
		material: Material, with_collision: bool = true) -> MeshInstance3D:
	if host == null:
		return null
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = pos
	mesh.rotation = Vector3(0.0, 0.0, angle_z)
	host.add_child(mesh)
	if with_collision:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		body.position = pos
		body.rotation = mesh.rotation
		host.add_child(body)
	return mesh


## Gruba kutu ekle (araç/character parçaları için — çarpışma yok).
func add_box_in(parent: Node3D, size: Vector3, pos: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = pos
	parent.add_child(mesh)
	return mesh


## Silindir ekle (direk, boru, sütun).
func add_cylinder(radius: float, height: float, pos: Vector3,
		material: Material, with_collision: bool = false,
		vertices: int = 12) -> MeshInstance3D:
	if host == null:
		return null
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = vertices
	cyl.rings = 1
	mesh.mesh = cyl
	mesh.material_override = material
	mesh.position = pos
	host.add_child(mesh)
	if with_collision:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		col.shape = shape
		body.add_child(col)
		body.position = pos
		host.add_child(body)
	return mesh


## Nokta ışığı ekle (gereksinim: her ışığın amacı olmalı).
func add_light(light: Light3D, pos: Vector3) -> Light3D:
	if host == null:
		return light
	light.position = pos
	host.add_child(light)
	return light
