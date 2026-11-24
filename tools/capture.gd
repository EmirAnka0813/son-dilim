extends SceneTree
##
## KONTROLLÜ EKRAN GÖRÜNTÜSÜ HARNESS
## ============================================================================
## Çalıştırma:
##   godot --resolution 1280x720 --script res://tools/capture.gd -- <out_dir>
##
## Her bölümü doğru pozisyonda, doğru kamera açısıyla tek tek çeker.
##
## Neden Movie Maker değil:
##   · Movie Maker oyuncunun "akış"ına bağlı — düşerse veya ışıksız alana
##     girerse siyah kare verir.
##   · Bu harness oyuncuyu KONTROLLÜ konuma koyar ve serbest kamera kullanır.
##
## Çıktı: <out_dir>/<view>.png
## ============================================================================

const VIEWS: Array[Dictionary] = [
	{"level": 0, "name": "ofis", "x": 8.0, "yaw": 0.0, "pitch": -0.12},
	{"level": 0, "name": "ofis-asansor", "x": 40.0, "yaw": 0.25, "pitch": -0.20},
	{"level": 0, "name": "ofis-plaza", "x": 54.0, "yaw": 0.1, "pitch": -0.08},
	{"level": 1, "name": "sokak", "x": 14.0, "yaw": -0.35, "pitch": -0.06},
	{"level": 1, "name": "sokak-trafik", "x": 24.0, "yaw": 0.0, "pitch": -0.08},
	{"level": 1, "name": "sokak-islak", "x": 42.0, "yaw": 0.0, "pitch": -0.14},
	{"level": 1, "name": "sokak-yaya", "x": 56.0, "yaw": 0.15, "pitch": -0.10},
	{"level": 1, "name": "sokak-insaat", "x": 72.0, "yaw": 0.0, "pitch": -0.10},
	{"level": 2, "name": "metro", "x": 14.0, "yaw": 0.0, "pitch": -0.10},
	{"level": 2, "name": "metro-platform", "x": 24.0, "yaw": 0.0, "pitch": -0.08},
	{"level": 2, "name": "metro-tunel", "x": 46.0, "yaw": 0.0, "pitch": -0.10},
	{"level": 3, "name": "yokus", "x": 14.0, "yaw": 0.0, "pitch": -0.06},
	{"level": 3, "name": "yokus-tepe", "x": 50.0, "yaw": 0.0, "pitch": -0.06},
	{"level": 3, "name": "ev", "x": 64.0, "yaw": 0.0, "pitch": 0.02},
]

var _out_dir: String = "res://shots"
var _main: Node = null
var _level_root: Node3D = null
var _player: Node3D = null
## Serbest kamera — oyun kamerasından bağımsız (deterministik görüntü).
var _cam: Camera3D = null
## Kamera hedefi (her karede uygulanır — bölüm yüklenirken kaybolmaz).
var _cam_focus := Vector3.ZERO
var _cam_pos := Vector3.ZERO
var _cam_pitch: float = 0.0
var _cam_yaw: float = 0.0
var _cam_locked: bool = false


func _init() -> void:
	print("\n=== SON DİLİM — EKRAN GÖRÜNTÜSÜ HARNESS ===\n")
	_run.call_deferred()


## Her karede kamerayı hedefe kilitle — bölüm yüklenirken konum kaymasın.
func _process(_delta: float) -> bool:
	if _cam_locked and _cam != null:
		_cam.global_position = _cam_pos
		var to_focus := _cam_focus - _cam_pos
		var horiz := Vector2(to_focus.x, to_focus.z).length()
		_cam.rotation = Vector3(
			atan2(to_focus.y, horiz),
			atan2(-to_focus.z, to_focus.x) + PI * 0.5,
			0.0)
	return false


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))

	var packed: PackedScene = load("res://res/scenes/Main.tscn")
	if packed == null:
		print("HATA: Main.tscn yüklenemedi")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame

	_level_root = _main.get("level_root")
	_player = _main.get("player")

	## Serbest kamera.
	_cam = Camera3D.new()
	_cam.fov = 72.0
	_cam.near = 0.05
	_cam.far = 400.0
	_cam.current = true
	root.add_child(_cam)

	## "--prologue" argümanı varsa prologue'u ATLAMA, onun ekranını çek.
	var shoot_prologue: bool = false
	for a in OS.get_cmdline_user_args():
		if a == "--prologue":
			shoot_prologue = true

	if shoot_prologue:
		## Prologue ekranı (SMS bildirimi + sohbet).
		for i in 40:
			await process_frame
		await RenderingServer.frame_post_draw
		var pimg: Image = root.get_texture().get_image()
		if pimg != null:
			pimg.save_png("%s/prologue-bildirim.png" % _out_dir)
			print("  ✓ prologue-bildirim")
		## Sohbeti aç (dokunma simülasyonu).
		for i in 90:
			await process_frame
		await RenderingServer.frame_post_draw
		var cimg: Image = root.get_texture().get_image()
		if cimg != null:
			cimg.save_png("%s/prologue-sohbet.png" % _out_dir)
			print("  ✓ prologue-sohbet")
		print("\n=== TAMAMLANDI ===\n")
		quit(0)
		return

	## Prologue'u kapat, oyunu başlat.
	var pro: Node = _main.get("prologue")
	if pro != null:
		pro.visible = false
	_main.call("begin_game")
	await create_timer(0.8).timeout

	## İLK bölüm için ön ısınma: level_root boşken yapılan ilk _load_level
	## çağrısında kamera yanlış yerde kalıyor. Bir kez yükle, sonra asıl
	## döngü başlasın.
	_main.call("_load_level", 0)
	for i in 20:
		await process_frame
	await create_timer(0.6).timeout

	for view: Dictionary in VIEWS:
		await _capture_view(view)

	print("\n=== TAMAMLANDI ===\n")
	quit(0)


## Tek bir görünümü yakala.
func _capture_view(view: Dictionary) -> void:
	var level_index: int = int(view["level"])
	var px: float = float(view["x"])
	var yaw: float = float(view["yaw"])

	## Kamera hedefi: oyuncunun biraz önü.
	var focus := Vector3(px + 3.0, 1.7, 0.0)
	var cam_dist: float = 8.5
	var cam_height: float = 3.4
	var dir := Vector3(cos(yaw), 0.0, sin(yaw))
	var cam_pos := focus - dir * cam_dist + Vector3(0.0, cam_height, 0.0)
	var to_focus := focus - cam_pos
	var horiz := Vector2(to_focus.x, to_focus.z).length()
	var pitch_angle := atan2(to_focus.y, horiz)
	var yaw_angle := atan2(-to_focus.z, to_focus.x) + PI * 0.5

	## Kamerayı BÖLÜM YÜKLENMEDEN ÖNCE ayarla + kilitle.
	_cam_focus = focus
	_cam_pos = cam_pos
	_cam_pitch = pitch_angle
	_cam_yaw = yaw_angle
	_cam_locked = true
	_cam.global_position = cam_pos
	_cam.rotation = Vector3(pitch_angle, yaw_angle, 0.0)

	## Bölümü yükle. İLK yüklemede eski bölüm hâlâ temizleniyor olabilir;
	## aynı bölümü ikinci kez yüklemek garantili temiz bir sahne verir.
	_main.call("_load_level", level_index)
	await process_frame
	_main.call("_load_level", level_index)
	for i in 20:
		await process_frame
	await create_timer(0.5).timeout
	await process_frame
	## Eski bölüm queue_free ile 1+ kare sonra silinir → bu sırada iki bölüm
	## birden durur. Doğru bölümü İSİM ile bul.
	var want_name: String = ["LevelOffice", "LevelStreet", "Level_Metro",
		"Level_Hill"][level_index]
	## Bolum yuklenene kadar bekle (isim + get_level_index eslesmesi).
	for i in 120:
		var found: bool = false
		for child in _level_root.get_children():
			if child.name == want_name:
				found = true
				break
		if found:
			break
		await process_frame
	## Yuklendikten sonra da biraz bekle (build_* fonksiyonlari _ready'de).
	for i in 10:
		await process_frame
	await create_timer(0.35).timeout
	await process_frame

	## Oyuncuyu konumlandır.
	if _player != null:
		_player.global_position = Vector3(px, 0.6, 0.0)
		_player.set("yaw", yaw)
		_player.set("pitch", float(view["pitch"]))
		_player.set("velocity", Vector3.ZERO)

	## Kamerayı yeniden uygula.
	_cam.global_position = cam_pos
	_cam.rotation = Vector3(pitch_angle, yaw_angle, 0.0)

	## Render için bekle.
	for i in 10:
		await process_frame
	## Kamerayı son kez uygula (bölüm kurulduktan sonra bozulmuş olabilir).
	_cam.global_position = cam_pos
	_cam.rotation = Vector3(pitch_angle, yaw_angle, 0.0)
	await process_frame
	await RenderingServer.frame_post_draw

	## Kaydet.
	var path: String = "%s/%s.png" % [_out_dir, view["name"]]
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("  %s: GÖRÜNTÜ ALINAMADI" % view["name"])
		return
	var err: int = img.save_png(path)
	if err != 0:
		print("  %s: KAYIT HATASI %d" % [view["name"], err])
		return
	## Tesis: dogru bolum yuklendi mi?
	var level_info: String = "YOK"
	for child in _level_root.get_children():
		if child.name == want_name:
			level_info = "%s(cocuk=%d)" % [child.name, child.get_child_count()]
			break
	print("  ✓ %s (level %d, x=%.0f) [%s]" % [view["name"], level_index, px,
		level_info])
