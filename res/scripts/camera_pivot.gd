extends Node3D
class_name CameraPivot
##
## KAMERA PİVOTU — 3D üçüncü şahıs yörünge kamerası
## ============================================================================
## Bu node, Player'ın KARDEŞİDİR (altı değil). Böylece:
##
##   · Karakterin dönüşü kamerayı DÖNDÜRMEZ.
##   · Kamera-göreli hareket hesabı karakterin dönüşünden bağımsızdır.
##   · "W" tuşu her zaman kameranın baktığı yöne götürür.
##
## ── 3D KAMERA MODELİ (YÖRÜNGE / ORBIT) ──────────────────────────────────────
##
## Kamera, karakterin ETRAFINDA bir YÖRÜNGE üzerinde durur:
##
##   elevation = -pitch        (fare yukarı/aşağı → yükseklik)
##   yaw                       (sağ tuş → yatay dönüş)
##   distance                 (omuz üstü mesafe)
##
## Kamera konumu (hedefe göre, YUKARIYU bakacak şekilde):
##
##   y   = pivot_yuksekligi + sin(elevation) · distance
##   r   = cos(elevation) · distance
##   x   = r · sin(yaw) + omuz_kaymasi · cos(yaw)
##   z   = r · cos(yaw) - omuz_kaymasi · sin(yaw)
##
## Sonra kamera HEDEFE BAKAR → karakter kadrajın alt-orta bölgesinde
## durur, zemin ve ufuk görünür → oyun 3D hissedilir.
##
## ÖNCEKI HATA ("oyun 3D, kamera 2D"): Kamera düz bakıyor ve karakter
## kadraja alınmıyordu. Sonra offset'in Y bileşeni yanlış hesaplanıyordu
## → kamera hep 2.05 m yükseklikte kalıyordu (2D hissi).
## Ölçülen: pitch=-0.70 iken beklenen 5.84 m, gerçek 2.05 m.
##
## BU DOSYADA: ofset doğrudan DÜNYA uzayında hesaplanır ve
## `camera.global_position` olarak atanır — yerel/pivot dönüşü
## karışmaz.
## ============================================================================

## Kameranın dünya uzayındaki yaw'u (radyan). Player tarafından beslenir.
var yaw: float = 0.0:
	set(value):
		yaw = value
		_update_camera_transform()

## Kameranın pitch'i (radyan). Player tarafından beslenir.
## Negatif = kamera aşağıdan bakar (yüksekten bakış).
var pitch: float = -0.18:
	set(value):
		pitch = value
		_update_camera_transform()

## Takip edilecek oyuncu (Player).
var target: Node3D = null

## Pivot'un karakter gövdesindeki yüksekliği (m).
@export var pivot_height: float = 1.72

## Kamera yörünge yarıçapı (m) — karakterden yatay uzaklık.
@export var camera_distance: float = 6.4
## Omuz kayması (m) — kamerayı yana alır, siluet görünür olur.
@export var shoulder_offset: float = 0.55
## Kameranın bakacağı noktanın hedefe göre yüksekliği (m).
@export var look_at_offset: float = 0.30
## Birinci şahıs modu açık mı?
var first_person: bool = false

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_update_camera_transform()


func _process(_delta: float) -> void:
	## Pivot, oyuncunun konumunu takip eder (DÖNÜŞÜ DEĞİL).
	if target != null and is_instance_valid(target):
		global_position = target.global_position + Vector3(0.0, pivot_height, 0.0)
	_update_camera_transform()


## Kameranın konumunu ve bakışını hesapla.
##
## ÖNEMLİ: Offset DÜNYA uzayında hesaplanır ve kamera.global_position
## olarak atanır. Böylece pivot'un kendi dönüşü hesaba KATILMAZ —
## (önceki hata: yerel ofset + pivot dönüşü = yanlış Y bileşeni).
func _update_camera_transform() -> void:
	if camera == null:
		return

	## Pivot'un konumu (hedef varsa).
	var pivot_pos: Vector3 = global_position
	if target != null and is_instance_valid(target):
		pivot_pos = target.global_position + Vector3(0.0, pivot_height, 0.0)
		global_position = pivot_pos

	if first_person:
		## ── BİRİNCİ ŞAHIS: kamera pivot'un tam ortasında ──
		camera.global_position = pivot_pos
		camera.rotation = Vector3(pitch, yaw, 0.0)
		camera.fov = 78.0
		return

	## ── ÜÇÜNCÜ ŞAHIS: YÖRÜNGE ──
	##
	## elevation = -pitch:
	##   pitch = -0.18 (varsayılan) → elevation = +0.18 → kamera hafif yüksekte
	##   pitch = -0.70 (fare yukarı) → elevation = +0.70 → kamera daha yüksekte
	##   pitch = +0.30 (fare aşağı) → elevation = -0.30 → kamera alçakta
	var elevation: float = -pitch
	var horiz_radius: float = cos(elevation) * camera_distance
	var vert_offset: float = sin(elevation) * camera_distance

	## Yatay bileşenler: yaw=0 → kamera +Z tarafında (arkada).
	var sin_y: float = sin(yaw)
	var cos_y: float = cos(yaw)
	var offset: Vector3 = Vector3(
		horiz_radius * sin_y + shoulder_offset * cos_y,
		vert_offset,
		horiz_radius * cos_y - shoulder_offset * sin_y)

	camera.global_position = pivot_pos + offset
	camera.fov = 70.0

	## HEDEFE BAK — karakter kadrajın alt-orta bölgesinde olsun.
	var look_point: Vector3 = pivot_pos + Vector3(0.0, look_at_offset, 0.0)
	if target != null and is_instance_valid(target):
		look_point = target.global_position + Vector3(0.0, look_at_offset + 0.45, 0.0)
	## Dik vektör ile bak (look_at'ın up vektörü dünya UP olmalı).
	var direction: Vector3 = look_point - camera.global_position
	if direction.length_squared() > 0.0001:
		camera.look_at(look_point, Vector3.UP)


## İlk şahıs moduna geç.
func set_first_person(enabled: bool) -> void:
	first_person = enabled
	_update_camera_transform()
