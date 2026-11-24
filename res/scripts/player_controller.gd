extends CharacterBody3D
class_name Player
##
## OYUNCU KONTROLLERİ — büyük abi
## ============================================================================
## Sorumluluklar:
##   1. Karakter hareketi (klavye, kamera-göreli)
##   2. Üçüncü şahıs kamera (sağ tuş sürükle) + birinci şahıs (V)
##   3. Pasta dengesine ivme bilgisini beslemek
##   4. Zıplama, sprint
##
## ── HAREKET MODELİ ─────────────────────────────────────────────────────────
## Godot'un CharacterBody3D'si "hareket et" + "kaydır" ayrımı kullanır:
##   velocity       : bu karedeki HEDEF hız (input + yerçekimi)
##   move_and_slide(): gerçek çarpışma çözümü + kayma
##
## Kamera-göreli yön:
##     forward = -camera.basis.z   (kameranın baktığı yön)
##     right   =  camera.basis.x
##     wish_dir = forward*input.z + right*input.x   (normalize)
##
## İvme ölçümü (denge sistemi için):
##     a = (v_now - v_prev) / delta
## Sert fren (a zıt yönde) → krem öne kaçar. Viraj (a yanal) → krem yana.
## ============================================================================

## ── HAREKET PARAMETRELERİ ──────────────────────────────────────────────────
@export_group("Hareket")
@export var walk_speed: float = 5.4
@export var sprint_speed: float = 9.2
## İvme (yer çekimi düşülmüş yatay hız hedefi).
@export var acceleration: float = 14.0
## Frenleme (yavaşlama) — sert fren kremi öne kaçırır, çocuk dostu olsun diye
## yumuşak tutulur.
@export var deceleration: float = 9.0
## Yerçekimi (yönü aşağı).
@export var gravity: float = 24.0
## Zıplama başlangıç hızı.
@export var jump_velocity: float = 8.5
## Hava kontrolü çarpanı (0 = havada yön verilemez).
@export var air_control: float = 0.35

@export_group("Kamera")
@export var camera_distance: float = 6.2
@export var camera_height: float = 1.55
## Kamera pivot'unun karakterin gövdesindeki yüksekliği (m).
@export var camera_pivot_height: float = 1.72
@export var camera_sensitivity: float = 0.0032
@export var camera_min_pitch: float = -1.25
@export var camera_max_pitch: float = 0.75
@export var camera_smoothing: float = 12.0

## ── SAHNE REFERANSLARI ─────────────────────────────────────────────────────
## Kamera pivot'u Player'ın KARDEŞİ (Main düzeyinde) — karakterin
## dönüşü kamerayı etkilemesin diye ayrı node.
@onready var camera_pivot: CameraPivot = null
@onready var camera: Camera3D = null
@onready var balance: CakeBalance = $CakeBalance
## Sırtta taşınan pasta kutusu (görsel).
@onready var cake_box: Node3D = $CakeBox
## Karakter gövdesi (koşu animasyonu için).
@onready var _body: Node3D = $Body

## ── DURUM ───────────────────────────────────────────────────────────────────
## Yatay hız (yön korunmadan).
var _horizontal_velocity: Vector2 = Vector2.ZERO
## Önceki kareki yatay hız (ivme ölçümü için).
var _prev_horizontal_velocity: Vector2 = Vector2.ZERO
## Kamera yaw (radyan).
var _yaw: float = 0.0
## Kamera pitch (radyan).
var _pitch: float = -0.18
## Pitch'i kamera pivot'u kendisi yönetiyor mu? (fare kontrolü)
var _pitch_managed_by_pivot: bool = false
## Birinci şahıs modu açık mı?
var first_person: bool = false
## Sıçrama tuşu basıldı mı (edge detection).
var _jump_pressed: bool = false
## Zıplama "coyote time" sayacı (kenardan yeni ayrıldıktan sonra zıplama izni).
var _coyote_timer: float = 0.0
## Zıplama tamponu (tuş erken basıldıysa hatırlanır).
var _jump_buffer: float = 0.0


func _ready() -> void:
	## ── KAMERA PİVOT'U BUL VE BAGLA ──
	##
	## CameraPivot Main düzeyinde, Player'ın kardeşi olarak durur.
	## Player'ın altında olsaydı karakterin dönüşü kamerayı döndürür ve
	## kamera-göreli hareket bozulurdu.
	var tree := get_tree()
	camera_pivot = null
	if tree != null:
		var main: Node = tree.root.get_node_or_null("Main")
		if main != null:
			camera_pivot = main.get_node_or_null("CameraPivot") as CameraPivot
	if camera_pivot != null:
		camera_pivot.target = self
		camera_pivot.yaw = _yaw
		camera_pivot.pitch = _pitch
		camera = camera_pivot.camera
		## Kamera pivot'un konumu HEMEN doğru olsun (ilk kare boş kalmasın).
		camera_pivot.global_position = global_position + Vector3(0, 1.72, 0)

	## Kameranın başlangıç yaw'ı karakterin baktığı yöne ayarla.
	_yaw = rotation.y
	_capture_mouse()
	## Kutu dokusu (Main hazır olduğunda).
	_apply_cake_texture()
	## Karakterin yönünü düzelt (GLB'de +Z'ye bakıyor, Godot'ta ileri -Z).
	##
	## NEDEN BURADA: .tscn içinde bir GLB instance'ının transform'u
	## override edilirse motor bunu farklı yorumlayabiliyor (ölçülen:
	## yüz hâlâ +Z'de kalıyordu). Runtime'da ayarlamak kesin.
	_fix_character_facing()


## Karakter mesh'ini -Z'ye bakacak şekilde döndür.
func _fix_character_facing() -> void:
	var char_node: Node3D = get_node_or_null("Body/Character")
	if char_node == null:
		return
	## 180° Y yaw. Basis satır satır: (-1,0,0 / 0,1,0 / 0,0,-1).
	char_node.transform = Transform3D(
		Vector3(-1, 0, 0),
		Vector3(0, 1, 0),
		Vector3(0, 0, -1),
		Vector3.ZERO)
	## Sırt çantası/pasta elde olduğu için kutu ayrı node — etkilenmez.


func _unhandled_input(event: InputEvent) -> void:
	## ── SAĞ FARE: KAMERA DÖNDÜRME (basılı tutup sürükle) ──
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_jump_buffer = 0.14

	elif event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		## Sağ tuş basılıyken fare delta'sı kamerayı döndürür.
		_yaw -= event.relative.x * camera_sensitivity
		_pitch = clampf(
			_pitch - event.relative.y * camera_sensitivity,
			camera_min_pitch, camera_max_pitch)
		## Pitch'i doğrudan pivot'a da yaz — pivot kameranın
		## sahibidir, player sadece öneri gönderir.
		if camera_pivot != null:
			camera_pivot.pitch = _pitch

	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_V:
				_toggle_first_person()
			KEY_ESCAPE:
				get_tree().paused = not get_tree().paused
				Input.set_mouse_mode(
					Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED)

	## Sıçramayı kaydet (edge detection).
	if event.is_action_pressed("jump"):
		_jump_pressed = true


## ── GİRDİ KONTROLÜ ─────────────────────────────────────────────────────────
## Girdi açık mı? (prologue sırasında kapalı — fizik döngüsü çalışmaya devam eder)
var input_enabled: bool = true
## Oyun içi test botu yönü (Vector2). Sıfır = normal oyuncu girdisi.
var _autopilot_direction: Vector2 = Vector2.ZERO


## Test botu için yön ayarla (headless doğrulama).
## NOT: Sadece test/otomasyon içindir — normal oyunda Vector2.ZERO kalır.
func set_autopilot(direction: Vector2) -> void:
	_autopilot_direction = direction


## Kamera yaw'ını doğrudan ayarla (test botu / kesişme için).
## NOT: _yaw her karede rotation.y'yi yönettiği için, doğrudan rotation.y
## yazmak EZİLİR. Bu yüzden _yaw'ı değiştiriyoruz.
func set_camera_yaw(yaw: float) -> void:
	## Kameranın MUTLAK yaw'ı. Karakterin gövdesi bundan BAĞIMSIZ.
	_yaw = yaw
	if camera_pivot != null:
		camera_pivot.yaw = yaw


## Girdiyi aç/kapat (prologue ↔ oyun).
func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		_jump_pressed = false
		_jump_buffer = 0.0
		_horizontal_velocity = Vector2.ZERO


func _physics_process(delta: float) -> void:
	## ── -1) KAMERA PİVOT'U (konum + yön) ──
	##
	## Pivot'un `target` referansı her karede teyit edilir: sahne
	## yeniden yüklendiğinde referans kopuyor ve kamera karakteri takip
	## etmiyordu (ölçülen: oyuncu 4.31 m, kamera 0.00 m).
	if camera_pivot != null:
		if camera_pivot.target != self:
			camera_pivot.target = self
		camera_pivot.yaw = _yaw
		## Pitch'in TEK sahibi PLAYER'dır (fare burada okunur).
		## `_pitch_managed_by_pivot` test/editor içindir: true iken player
		## pitch'i EZMEZ, pivot kendi değerini korur.
		if not _pitch_managed_by_pivot:
			camera_pivot.pitch = _pitch

	## ── 0) DENGE GİRDİSİ (Q/E) ──
	##
	## ÖLÇÜLEN MANTIK HATASI: Hem `balance.add_correction()` hem
	## `balance.set_manual_input()` çağrılıyordu ve ikisi de Q/E okuyordu
	## (balance_left = Q = 81, tilt_left = Q = 81). Sonuç: tek tuş basışı
	## kutuyu İKİ KEZ düzeltiyordu → denge mekaniği gereksiz yere
	## "kendi kendini düzeltiyor" gibi görünüyordu.
	##
	## DOĞRU TASARIM — iki ayrı mekanik:
	##   · add_correction(): "kutu düzelt" eylemi — hedef açıyı KAYDIRIR
	##     (kutu eğikken düzeltmek için basılı tut).
	##   · set_manual_input(): sürekli hedef — oyuncu kutuyu belirli bir
	##     açıda TUTMAK istiyorsa.
	##
	## Bunlar ÇELİŞMELİ: add_correction hedefi kaydırır, set_manual_input
	## ise hedefi her karede AYNI değere çeker. İkisi birlikte çalışınca
	## düzeltme etkisiz kalır.
	##
	## ÇÖZÜM: add_correction KULLANILIR (daha oyuncu-oyuncu ve "basılı
	## tutarak düzelt" hissi verir), set_manual_input KULLANILMAZ.
	## Böylece tek bir mekanizma, öngörülebilir davranış.
	var balance_input: float = 0.0
	if input_enabled:
		if Input.is_action_pressed("balance_left"):
			balance_input -= 1.0
		if Input.is_action_pressed("balance_right"):
			balance_input += 1.0
	if balance_input != 0.0:
		## Düzeltme gücü: delta ile ölçekli (frame-rate bağımsız).
		balance.add_correction(balance_input, 2.2 * delta * 60.0)

	## ── 1) YERÇEKİMİ ──
	if not is_on_floor():
		velocity.y -= gravity * delta
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
	else:
		_coyote_timer = 0.12

	## ── 2) HAREKET YÖNÜ (kamera-göreli) ──
	var input_vector: Vector2 = Vector2.ZERO
	if input_enabled:
		input_vector = Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back")
		## OYUN İÇİ TEST BOTU: dışarıdan yön verilebilir. Headless testlerde
		## Input.parse_input_event fizik döngüsüne güvenilir ulaşmadığı için
		## bot bu yolu kullanır. Normal oyunda Vector2.ZERO kalır.
		if _autopilot_direction != Vector2.ZERO:
			input_vector = _autopilot_direction
	var wish_direction: Vector3 = Vector3.ZERO

	if input_vector.length_squared() > 0.001:
		## ── KAMERA-GÖRELİ YÖN ──
		##
		## ÖLÇÜLEN HATA: `camera.global_transform.basis.z` kullanılıyordu.
		## Kamera, karakterin (`Player`) altındaki `CameraPivot` içinde
		## olduğu için kamera.global_transform KARAKTERİN DÖNÜŞÜNÜ de
		## içeriyordu. Karakter döndüğünde kamera da dönüyor ve
		## "W" bastığında oyuncu NEREDEYSE HİÇ KIMILAMADIYORDU
		## ("yürüme ayarını bozmuşsun" şikayeti).
		##
		## DOĞRU ÇÖZÜM: Kamera yönünü MUTLAK yaw'dan hesapla —
		## karakterin dönüşünden bağımsız.
		##
		## _yaw = kameranın dünya uzayındaki yaw'ı (radyan).
		## yaw=0 → kamera -Z'ye bakar.
		## yaw=PI/2 → kamera -X'e bakar.
		var cam_yaw: float = _yaw
		var forward: Vector3 = Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
		var right: Vector3 = Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
		wish_direction = (forward * -input_vector.y + right * input_vector.x).normalized()

	## ── 3) HIZ HEDEFİ ──
	var target_speed: float = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var target_velocity: Vector2 = Vector2(wish_direction.x, wish_direction.z) * target_speed

	var control: float = 1.0 if is_on_floor() else air_control
	if target_velocity.length_squared() > 0.001:
		_horizontal_velocity = _horizontal_velocity.move_toward(target_velocity, acceleration * control * delta)
	else:
		## Frenleme: sert olursa krem öne kaçar. Daha yumuşak tutuyoruz ki
		## çocuk zorlanmasın, ama yine de fark edilsin.
		_horizontal_velocity = _horizontal_velocity.move_toward(
			Vector2.ZERO, deceleration * delta)

	velocity.x = _horizontal_velocity.x
	velocity.z = _horizontal_velocity.y

	## ── 4) ZIPLAMA ──
	if _jump_buffer > 0.0:
		_jump_buffer -= delta
	if input_enabled and (_jump_pressed or (_jump_buffer > 0.0 and _coyote_timer > 0.0)):
		if _coyote_timer > 0.0:
			velocity.y = jump_velocity
			_jump_buffer = 0.0
			_coyote_timer = 0.0
			## Zıplama kutuya ani sarsıntı verir (kutu yukarı savrulur).
			balance.add_impulse(randf_range(-0.35, 0.35))
			## Zıplama sesi (GameManager üzerinden tetiklenir).
			var gm: Node = get_tree().get_first_node_in_group("game_manager")
			if gm and gm.has_method("play_sfx"):
				gm.play_sfx("jump")
	_jump_pressed = false

	## ── 5) HAREKET ──
	move_and_slide()

	## ── 6) İVME ÖLÇÜMÜ → DENGE SİSTEMİ ──
	var current_horizontal: Vector2 = Vector2(velocity.x, velocity.z)
	var accel: Vector2 = Vector2.ZERO
	if delta > 0.0001:
		accel = (current_horizontal - _prev_horizontal_velocity) / delta
	## Aşırı ivme değerlerini yumuşat (çarpışma anında spike olur).
	accel = accel.limit_length(60.0)
	balance.apply_acceleration(Vector3(accel.x, 0.0, accel.y))
	_prev_horizontal_velocity = current_horizontal

	## ── 7) DENGE GİRDİSİ (Q/E) ──
	##
	## NOT: `balance.set_manual_input()` BURADA ÇAĞRILMAZ. Bölüm 0'da
	## `add_correction()` kullanılıyor; ikisi birlikte çalışınca hedef
	## açı her karede ezilir ve düzeltme etkisiz kalır (ölçülen hata).
	## Düzeltme bırakılınca kutu ortalamaya dönsün.
	if balance_input == 0.0:
		balance.clear_manual_input()

	## ── 8) GÖRSEL: kutu sırtta, koşuyla sallanır ──
	_update_cake_visuals(delta)

	## ── 9) KAMERA ──
	_update_camera(delta)


## ═══════════════════════════════════════════════════════════════════════════
## Pasta kutusuna karton dokusunu uygula (varsa).
func _apply_cake_texture() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var main: Node = tree.root.get_node_or_null("Main")
	if main == null or not main.has_method("texture"):
		return
	var tex: Texture2D = main.call("texture", "box_diffuse")
	if tex == null:
		return
	for child in cake_box.get_children():
		if child is MeshInstance3D:
			var mesh: MeshInstance3D = child
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_texture = tex
			mat.uv1_scale = Vector3(2, 2, 2)
			mat.roughness = 0.85
			mesh.material_override = mat


## GÖRSEL: PASTA KUTUSU + KARAKTER
## ═══════════════════════════════════════════════════════════════════════════
func _update_cake_visuals(delta: float) -> void:
	## Pasta kutusu sırtta → koşu ritmiyle hafifçe sallanır.
	## Denge açısı kutuyu eğdirir: oyuncu ne kadar eğdiyse kutu o kadar yan.
	var run_phase: float = _horizontal_velocity.length() / maxf(walk_speed, 0.01)
	var bob: float = sin(run_phase * 9.0) * 0.03 * clampf(run_phase, 0.0, 1.0)

	## Kutu ELDE: denge açısı kutuyu Z ekseninde (sağa-sola) eğirir.
	cake_box.rotation.z = lerp(cake_box.rotation.z, -balance.angle, 10.0 * delta)
	## Kosu ritmiyle hafif dikey salinim.
	cake_box.position.y = 1.26 + bob
	cake_box.position.z = 0.52
	## Kutu hafif egik durur (dogal tasima durusu).
	cake_box.rotation.x = -0.10 + sin(run_phase * 6.0) * 0.03

	## ── KARAKTER YÖNÜ: HAREKET YÖNÜNE döner ──
	##
	## ÖLÇÜLEN HATA: Karakter kameranın baktığı yöne (_yaw) dönüyordu.
	## Bu yanlış: geri giderken karakter öne bakıyordu (yüzü kameraya
	## dönük kalıyordu), çapraz giderken de yönü tutmuyordu.
	##
	## DOĞRU DAVRANIŞ (Roblox / TPS standardı): Karakter HİZ YÖNÜNE döner.
	## Kamera ayrı bir yaw'a sahiptir; karakter onu takip etmez.
	var speed: float = _horizontal_velocity.length()
	if speed > 0.35:
		## Hız yönü (dünya uzayında, X/Z düzlemi).
		##
		## Vector2 = (x, z). Godot'ta karakterin ileri yönü -Z'dir.
		## Yön formülü: yaw = atan2(-x, -z)
		##   • +X hareket → atan2(-1, 0) = -PI/2  → -Z ekseni +X'e döner ✓
		##   • +Z hareket → atan2(0, -1) = PI      → karakter +Z'ye bakar ✓
		##   • -Z hareket → atan2(0, 1) = 0        → karakter -Z'ye bakar ✓
		var move_dir: Vector2 = _horizontal_velocity / speed
		var target_yaw: float = atan2(-move_dir.x, -move_dir.y)
		##
		## ÖNEMLİ: Bu dönüş SADECE gövdeye uygulanır, `Player`ın
		## `rotation.y`'sine DEĞİL. Karakter dönerken kamera yerinde
		## kalır ve "W" kameranın baktığı yöne götürmeye devam eder.
		##
		## (Ölçülen hata: `rotation.y` yazılınca CameraPivot da dönüyordu
		## → kamera-göreli hareket bozuluyordu → "W" neredeyse kımılamıyordu.)
		_body.rotation.y = lerp_angle(_body.rotation.y, target_yaw, 14.0 * delta)
	else:
		## Duruyorken gövde kameranın yönüne dönsün (durgun görünüm).
		_body.rotation.y = lerp_angle(_body.rotation.y, _yaw, 8.0 * delta)

	## Koşu ritmi: gövde hafifçe öne eğilir ve zıplar.
	## (GLB birleşik olduğu için kolları ayrı döndüremiyoruz — gövde
	##  eğilmesiyle koşu hissi verilir.)
	var run_amount: float = clampf(run_phase, 0.0, 1.0)
	var lean: float = run_amount * 0.16
	var hop: float = abs(sin(run_phase * 9.0)) * 0.04 * run_amount
	_body.rotation.x = lerp(_body.rotation.x, lean, 10.0 * delta)
	_body.position.y = lerp(_body.position.y, hop, 12.0 * delta)
	## Zıplarken gövde öne eğilir.
	if not is_on_floor():
		_body.rotation.x = lerp(_body.rotation.x, 0.12, 6.0 * delta)


## ═══════════════════════════════════════════════════════════════════════════
## KAMERA
## ═══════════════════════════════════════════════════════════════════════════
func _update_camera(delta: float) -> void:
	## ── KAMERA: PİVOT'A DEVRET ──
	##
	## Pivot (Main düzeyinde) konumu, yörünge geometrisini ve bakışı
	## kendisi yönetir. Burada sadece mod değişimini bildiriyoruz.
	## (yaw/pitch _physics_process'in başında yazılıyor.)
	if camera_pivot == null:
		return
	camera_pivot.set_first_person(first_person)


func _toggle_first_person() -> void:
	first_person = not first_person
	if camera_pivot != null:
		camera_pivot.set_first_person(first_person)
	## Karakter gövdesi birinci şahısta gizlenir (kafa hariç — kamera içinde).
	$Body.visible = not first_person
	$CakeBox.visible = not first_person


func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## ── TEST / HAT FİKRİ DÖNÜŞÜ ───────────────────────────────────────────────
## Checkpoint'ten dönüldüğünde ya da yeni bölüm başladığında çağrılır.
func reset_to(spawn_position: Transform3D) -> void:
	global_position = spawn_position.origin
	rotation.y = spawn_position.basis.get_euler().y
	velocity = Vector3.ZERO
	_horizontal_velocity = Vector2.ZERO
	_prev_horizontal_velocity = Vector2.ZERO
	_yaw = rotation.y
	_pitch = -0.18
	if camera_pivot != null:
		camera_pivot.yaw = _yaw
		camera_pivot.pitch = _pitch
	balance.reset()
	_body.rotation.x = 0.0
	_body.rotation.y = 0.0
	_body.position.y = 0.0
	_jump_buffer = 0.0
	_jump_pressed = false
	first_person = false
	$Body.visible = true
	$CakeBox.visible = true
