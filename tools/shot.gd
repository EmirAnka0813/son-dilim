extends SceneTree
##
## EKRAN GÖRÜNTÜSÜ ALICI (headless değil — gerçek pencere gerekir)
## Çalıştırma:
##   godot --script res://tools/shot.gd -- <sahne> <cikti.png> <kare_sayisi>
##
## Not: headless modda viewport çizilmez. Bu betik "rendering method" ile
## gerçek pencere açar ve görüntüyü kaydeder.
##

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://res/scenes/Main.tscn"
	var out_path: String = args[1] if args.size() > 1 else "res://shot.png"
	var frames: int = int(args[2]) if args.size() > 2 else 120

	var packed: PackedScene = load(scene_path)
	if packed == null:
		print("SAHNE YUKLENEMEDI: ", scene_path)
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	root.add_child(_make_camera())

	## Prologue varsa atla (4. argüman "skip" ise).
	## _ready() tamamlansın (referanslar hazır olsun).
	await process_frame
	await process_frame

	var skip: bool = args.size() > 3 and args[3] == "skip"
	if skip and scene.has_node("Prologue"):
		var pro: Node = scene.get_node("Prologue")
		pro.visible = false
		## Prologue'u gizle + oyunu başlat.
		if scene.has_method("begin_game"):
			scene.call("begin_game")
			await create_timer(1.5).timeout

	for i in frames:
		await process_frame

	## Ekran görüntüsü — oyunun kendi viewport'undan (daha güvenilir).
	if scene.has_method("save_shot"):
		scene.call("save_shot", out_path)
		await create_timer(1.0).timeout
		quit(0)
		return
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("GORSEL ALINAMADI (headless?)")
		quit(1)
		return
	var err: int = img.save_png(out_path)
	print("KAYDEDILDI: ", out_path, " hata=", err, " boyut=", img.get_width(), "x", img.get_height())
	quit(0)


## Render için kamera (sahne kendi kamerası yoksa).
func _make_camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(4, 3, 10)
	cam.rotation_degrees = Vector3(-15, 0, 0)
	return cam
