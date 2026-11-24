extends Node3D
##
## ANA SAHNE DENETLEYİCİSİ
## ============================================================================
## Sorumlulukları:
##   · Level sahnesini yüklemek ve değiştirmek
##   · GameManager / Player / UI arasındaki bağlantıları kurmak
##   · Prologue → Oyun akışını yönetmek
##   · Checkpoint'leri kaydetmek
## ============================================================================

const LEVEL_SCENES: Array[String] = [
	"res://res/scenes/Level_Office.tscn",
	"res://res/scenes/Level_Street.tscn",
	"res://res/scenes/Level_Metro.tscn",
	"res://res/scenes/Level_Hill.tscn",
]

## Bölüm sonunda çağrılır (level_exit_zone gibi bir objeden).
## Sahne değiştirir ve oyuncuyu yeni bölümün başlangıcına koyar.
func advance_to_next_level() -> void:
	if _transitioning:
		return
	_transitioning = true
	_fade_out_and_in(func() -> void:
		_load_level(game.current_level + 1)
		game.current_level += 1
		game.level_changed.emit(game.current_level)
		player.reset_to(Transform3D(Basis(), Vector3(2, 0.1, 0)))
		game.score += 300
		game.score_changed.emit(game.score)
	)
	## Geçiş bittiğinde bayrağı indir (perde tamamen kapandıktan sonra).
	var t := create_tween()
	t.tween_interval(0.85)
	t.tween_callback(func() -> void: _transitioning = false)

@onready var level_root: Node3D = $LevelRoot
@onready var final_screen: Control = $FinalScreen
## Prologue bir CanvasLayer (UI'in üstünde görünsün diye, layer=2).
@onready var prologue: CanvasLayer = $Prologue
@onready var player: Player = $Player
@onready var ui: UIController = $UI
@onready var game: GameManager = $GameManager

## Yüklü bölüm sahnesinin örneği (checkpoint'i bulmak için).
var _current_level: Node3D = null
## Bölüm geçişinde kullanılan siyah perde.
var _fade: ColorRect = null
## Bölüm geçişi sürüyor mu? (exit zone'un tekrar tetiklenmesini önler)
var _transitioning: bool = false


## Geliştirme: otomatik ekran görüntüsü.
##   godot --script res://tools/shot.gd -- <sahne> <cikti> <kare> skip
## Otomatik mod: --auto-shot=<yol> argümanı verilirse oyun başladıktan
## N kare sonra görüntü alır.
var _auto_shot_path: String = ""
var _auto_shot_frame: int = 0
var _auto_shot_target: int = 0
var _skip_prologue: bool = false
## Gorsuntu icin bölüm / X konumu (paketlenmis oyundan kanit icin).
var _shot_level: int = 0
var _shot_level_set: bool = false
var _shot_x: float = 2.0
var _shot_x_set: bool = false
## Prologue ekraninin goruntusunu al (baslatma akisi kaniti).
var _shot_prologue: bool = false
## Otomatik çekim açık mı? (walk modunda kapatılır).
var _auto_shot_enabled: bool = true
## Kameranın yaw'u (derece) ve karakterin yürüyüş modu.
var _shot_yaw: float = 0.0
var _shot_yaw_set: bool = false
var _shot_walk: bool = false


func _ready() -> void:
	_make_fade_overlay()
	_setup_audio()
	_setup_textures()
	_setup_auto_shot()
	## Prologue'un CanvasLayer katmanini garanti et.
	## (Scene dosyasinda layer=2 var ama instance override'i veya
	## import sirasinda kaybolabiliyor — build'de layer 0'a dustugu
	## icin HUD butonu ortuyordu.)
	## NOT: CanvasLayer'da `visible` ÖZELLİĞİ YOK (CanvasItem'ten gelir,
	## CanvasLayer Node tabanlıdır). Sadece `layer` ve `offset` vardır.
	if prologue is CanvasLayer:
		prologue.layer = 2
	_load_level(0)
	_connect_all()
	## ── PROLOGUE AKIŞINI BURDAN BAŞLAT ──
	##
	## ÖLÇÜLEN HATA: Prologue'un kendi `_ready()`'si build'de ÇAĞRILMIYORDU
	## (teşhis dosyası boş kalıyordu). CanvasLayer bir CanvasItem DEĞİLDİR
	## ve `_ready` sıralaması farklı çalışabiliyor.
	##
	## Çözüm: Main, akışı KENDI `_ready`'sinde başlatır — Main'in
	## `_ready`'si her zaman çalışır.
	if not _skip_prologue and not _shot_prologue:
		## Prologue sırasında oyuncu girdisi kapalı (fizik çalışmaya devam eder).
		player.set_input_enabled(false)
		if prologue != null and prologue.has_method("start_prologue"):
			prologue.call("start_prologue")
	if _shot_prologue:
		## Prologue ekraninin goruntusu.
		##
		## KRİTİK: _start_prologue() ÇAĞRILMALI. Prologue'un kendi
		## _ready()'i akışı başlatır (bildirim → chat → mesajlar → buton).
		## Bu branch'te çağrılmadığı için buton hiç belirmiyordu ve
		## ekran 3D sahneyi gösteriyordu (p50=18, uniq=224).
		if prologue != null and prologue.has_method("start_prologue"):
			prologue.call("start_prologue")
		## Prologue'u KESIN gorunur yap — hem PhoneScreen hem buton.
		var _phone: Control = prologue.get_node_or_null("PhoneScreen")
		if _phone != null:
			_phone.visible = true
			_phone.modulate = Color(1, 1, 1, 1)
		## Otomatik çekimi KAPAT — biz 17 sn sonra kendimiz çekeceğiz.
		##
		## ÖLÇÜLEN HATA: _process 150. karede (~2.5 sn) görüntü alıp oyunu
		## kapatıyordu. Prologue'un 10 sn'lik akışı (buton belirmesi)
		## hiç tamamlanamıyordu — teşhis dosyası sadece t=2.0'a kadar
		## kayıt vardı.
		_auto_shot_enabled = false
		## 17 sn: buton kesin gorunur.
		_shot_prologue_timer(17.0)
	elif _skip_prologue:
		## Prologue'u gizle ve doğrudan oyuna gir.
		## (Prologue bir CanvasLayer → altındaki Control gizlenir.)
		prologue.get_node("PhoneScreen").visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		player.set_physics_process(true)
		game.start_game()
		## Istenen bölümü yükle (paketlenmis oyun kaniti icin).
		if _shot_level_set and _shot_level > 0:
			_load_level(_shot_level)
		## Oyuncuyu istenen konuma koy.
		if _shot_x_set:
			player.global_position = Vector3(_shot_x, 0.6, 0.0)
		## Kameranın yaw'unu ayarla.
		if _shot_yaw_set:
			player.call("set_camera_yaw", _shot_yaw)
		## Karakter yürürken görüntü al.
		if _shot_walk:
			## 5 sn: bölüm yüklensin, ışıklar otursun.
			_shot_walk_timer(5.0)
			## Otomatik çekimi KAPAT (walk modunda biz çekeceğiz).
			## Çok büyük hedef vermek oyunu sonsuza kadar açık tutuyordu.
			_auto_shot_enabled = false
	else:
		## Akış yukarıda (Main._ready) zaten başlatıldı — çift başlatma yok.
		pass


## ── DOKU SİSTEMİ ───────────────────────────────────────────────────────────
## Prosedürel olarak üretilmiş albedo + normal haritaları (tools/make_textures).
## Üretim: Python ile tileable value-noise → PNG.
##
##   asphalt_albedo / asphalt_normal    → yol zemini
##   pavement_albedo / pavement_normal  → kaldırım
##   box_diffuse                        → pasta kutusu
##   facade_albedo                      → bina cephesi
##
## Dokular bir kez yüklenir ve statik malzemelere uygulanır (level scriptleri
## kendi materyallerini oluştururken bunları kullanır).
var _textures: Dictionary = {}


func _setup_textures() -> void:
	## TextureLoader yerine doğrudan load() — .import varsa daha hızlı.
	for key in ["asphalt_albedo", "asphalt_normal", "pavement_albedo",
			"pavement_normal", "box_diffuse", "facade_albedo"]:
		var path: String = "res://res/assets/textures/%s.png" % key
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			if tex:
				_textures[key] = tex


## Texture'ı al (yoksa null).
func texture(key: String) -> Texture2D:
	return _textures.get(key, null)


## ── SES SİSTEMİ ────────────────────────────────────────────────────────────
## Her ses için bir AudioStreamPlayer. Sıfır maliyet: WAV dosyaları Python ile
## üretildi (BFXR tarzı arcade sentezi).
##
## Kaynak dosyalar:
##   footsteps.wav  car_horn.wav  timer_tick.wav  failure.wav  success.wav
##   slip_warning.wav  bump.wav  jump.wav  ambient_rain.wav  pickup.wav
var _sfx: Dictionary = {}
var _music: AudioStreamPlayer = null
var _ambience: AudioStreamPlayer = null


func _setup_audio() -> void:
	_sfx = {
		"footsteps": _make_player("res://res/assets/audio/footsteps.wav", -8.0),
		"car_horn": _make_player("res://res/assets/audio/car_horn.wav", -6.0),
		"timer_tick": _make_player("res://res/assets/audio/timer_tick.wav", -10.0),
		"failure": _make_player("res://res/assets/audio/failure.wav", -3.0),
		"success": _make_player("res://res/assets/audio/success.wav", -3.0),
		"slip_warning": _make_player("res://res/assets/audio/slip_warning.wav", -6.0),
		"bump": _make_player("res://res/assets/audio/bump.wav", -6.0),
		"jump": _make_player("res://res/assets/audio/jump.wav", -9.0),
		"pickup": _make_player("res://res/assets/audio/pickup.wav", -6.0),
	}
	## Arka plan müziği (temposu süre azaldıkça artar — GameManager yönetir).
	_music = _make_looping_player("res://res/assets/audio/ambient_rain.wav", -12.0)
	## Yağmur ortam sesi.
	_ambience = _make_looping_player("res://res/assets/audio/ambient_rain.wav", -16.0)
	_ambience.play()


func _make_player(path: String, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream: AudioStream = load(path)
	if stream:
		player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


## Döngüsel çalan oynatıcı (loop bayrağı stream'in kendisinde ayarlanır).
func _make_looping_player(path: String, volume_db: float) -> AudioStreamPlayer:
	var player := _make_player(path, volume_db)
	var stream: AudioStream = player.stream
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = 0
	return player


## Belirli bir sesi çal.
func play_sfx(sound: String) -> void:
	if _sfx.has(sound):
		var p: AudioStreamPlayer = _sfx[sound]
		p.play()


## ── BÖLÜM YÜKLEME ──────────────────────────────────────────────────────────
func _load_level(index: int) -> void:
	if index < 0 or index >= LEVEL_SCENES.size():
		push_error("Geçersiz bölüm indeksi: %d" % index)
		return
	## Eski bölümü temizle.
	##
	## ÖNEMLİ: queue_free() tek BAŞINA yetmez — node 'free' olana kadar
	## level_root'un çocuğu olarak kalır. Yeni bölüm eklenirken isim çakışması
	## olur (@LevelOffice@2) ve iki bölüm aynı anda aktif kalır (çarpışma,
	## ışık ve kontrol hataları). Bu yüzden ÖNCE remove_child, sonra queue_free.
	if _current_level:
		level_root.remove_child(_current_level)
		_current_level.queue_free()
		_current_level = null
	## Yeni bölümü kur.
	var packed: PackedScene = load(LEVEL_SCENES[index])
	if packed == null:
		push_error("Bölüm yüklenemedi: %s" % LEVEL_SCENES[index])
		return
	_current_level = packed.instantiate()
	level_root.add_child(_current_level)
	## Bölümdeki checkpoint'leri GameManager'a kaydet.
	_register_level_checkpoints()
	## Bölüm çıkışını bağla (get_exit_position varsa).
	##
	## ÖNEMLİ: Area3D'nin collision_mask'i oyuncuyu algılayacak şekilde
	## AYARLANMALI. Varsayılan mask 1'dir ve oyuncu collision_layer=2'de
	## olduğu için ALGILANMAZDI — bölüm çıkışı hiç çalışmıyordu.
	##
	## Ayrıca mask 1'e açık olursa ZEMİN (StaticBody, layer 1) de tetikleyip
	## bölümü atlatabiliyor. Bu yüzden sadece oyuncu katmanı (2) dinlenir.
	if _current_level != null and _current_level.has_method("get_exit_position"):
		var exit_pos: Vector3 = _current_level.get_exit_position()
		var zone := Area3D.new()
		zone.position = exit_pos
		## Yalnızca oyuncu katmanını (collision_layer = 2) dinle.
		zone.collision_layer = 0
		zone.collision_mask = 2
		## Birden fazla gövde girmesin (aynı karede 2 kez tetiklenmesin).
		zone.monitoring = true
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 6.0, 10.0)
		shape.shape = box
		zone.add_child(shape)
		zone.body_entered.connect(_on_level_exit_entered)
		_current_level.add_child(zone)


func _register_level_checkpoints() -> void:
	if not _current_level:
		return
	## Checkpoint'ler bölümün KENDİ script'inde (Level_Office / Level_Street),
	## çocuk node'larında değil.
	if _current_level.has_method("get_checkpoint_transforms"):
		for transform: Transform3D in _current_level.get_checkpoint_transforms():
			game.register_checkpoint(transform)


## ── BAĞLANTILAR ────────────────────────────────────────────────────────────
func _connect_all() -> void:
	game.bind_scene(player, player.balance, _music, _sfx.get("timer_tick"))
	ui.bind(game, player.balance)
	## Denge uyarisi -> ses.
	player.balance.slip_warning.connect(func() -> void:
		play_sfx("slip_warning"))
	player.balance.cake_dropped.connect(func() -> void:
		play_sfx("failure"))
	## Oyun sonu sesleri.
	game.game_ended.connect(func(reason: int, _score: int) -> void:
		if reason == GameManager.EndReason.ARRIVED:
			play_sfx("success")
	)
	game.game_ended.connect(_on_game_ended)


## ── PROLOGUE ────────────────────────────────────────────────────────────────
func _start_prologue() -> void:
	## Prologue: oyun durumu PROLOGUE, oyuncu bekler.
	game.state = GameManager.State.PROLOGUE
	## Kamerayı sinematik bir açıya al (ofis görünümü için).
	player._yaw = 0.6
	player._pitch = -0.10
	## Fareyi serbest bırak (prologue'da imleç görünsün).
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	## Oyuncu hareket edemesin: FİZİK DÖNGÜSÜNÜ KAPATMIYORUZ (bölüm
	## yükleme/fizik simülasyonu çalışmaya devam etmeli). Sadece girdiyi
	## engelliyoruz — player_controller'da "input_enabled" bayrağı ile.
	player.set_input_enabled(false)




## Prologue bittiğinde çağrılır (butona basılınca).
func begin_game() -> void:
	## Oyun 1. bölümden başlar.
	game.current_level = 0
	game.start_game()
	## Oyuncunun girdisi açılsın.
	player.set_input_enabled(true)
	## NOT: Bölüm zaten _ready'de yüklendi (_load_level(0)). Burada TEKRAR
	## yüklemek çift bölüm demek — oyuncu eski bölümde kalır, yenisi ışıksız
	## kalır. Sadece oyuncuyu başlangıç noktasına koy.
	_fade_out_and_in(func() -> void:
		player.reset_to(Transform3D(Basis(), Vector3(2, 0.1, 0)))
	)


## ── PERDE ───────────────────────────────────────────────────────────────────
func _make_fade_overlay() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


func _fade_out_and_in(action: Callable) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.35)
	tween.tween_callback(action)
	tween.tween_property(_fade, "color:a", 0.0, 0.45)


## ── BÖLÜM ÇIKIŞI ───────────────────────────────────────────────────────────
func _on_level_exit_entered(_body: Node3D) -> void:
	## Exit zone'a girildi. Tekrar tetiklenmeyi önle (bölüm yüklenirken
	## oyuncu yeni bölümün başlangıcında olabilir).
	if _transitioning:
		return
	if game.state != GameManager.State.PLAY:
		return
	if game.current_level + 1 < LEVEL_SCENES.size():
		advance_to_next_level()
	else:
		## Son bölüm bitti → mutlu son.
		game._end_game(GameManager.EndReason.ARRIVED)


## ── OTOMATİK EKRAN GÖRÜNTÜSÜ ──────────────────────────────────────────────
## Komut satırından --auto-shot=<yol> okunur.
## Prologue goruntusu icin gecikmeli cekim.
func _shot_prologue_timer(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if _auto_shot_path.is_empty():
		return
	## Çekim anında butonu zorla goster (akış ne olursa olsun).
	var _p: Control = prologue.get_node_or_null("PhoneScreen")
	if _p != null:
		_p.visible = true
		_p.modulate = Color(1, 1, 1, 1)
	var _b: Button = prologue.get_node_or_null("StartButton")
	if _b != null:
		_b.visible = true
		_b.disabled = false
		_b.modulate = Color(1, 1, 1, 1)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		var err: int = img.save_png(_auto_shot_path)
		print("PROLOGUE GÖRÜNTÜ KAYDEDİLDİ: %s hata=%d" % [_auto_shot_path, err])


## Karakter yürürken görüntü al (yön doğrulaması).
##
## Karakter "ileri" (W) yönünde yürürken çekilir — böylece gövdenin
## HIZ YÖNÜNE döndüğü görsel olarak doğrulanır.
func _shot_walk_timer(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	## W tuşu basili — karakter kameranın baktığı yöne yürür.
	var ev := InputEventAction.new()
	ev.action = "move_forward"
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)
	await get_tree().create_timer(2.5).timeout
	## Tuşu bırak.
	var up := InputEventAction.new()
	up.action = "move_forward"
	up.pressed = false
	up.strength = 0.0
	Input.parse_input_event(up)
	await get_tree().process_frame
	if not _auto_shot_path.is_empty():
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		if img != null:
			var err: int = img.save_png(_auto_shot_path)
			print("GÖRÜNTÜ KAYDEDİLDİ: %s hata=%d" % [_auto_shot_path, err])
	## Çekim bitti — oyunu kapat (headless test sonsuza kadar beklemesin).
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


func _setup_auto_shot() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--auto-shot="):
			_auto_shot_path = arg.substr(12)
			_auto_shot_frame = 0
			_auto_shot_target = 150
		elif arg == "--skip-prologue":
			## Prologue'u atla → doğrudan oyuna gir.
			_skip_prologue = true
		elif arg.begins_with("--shot-level="):
			## Hangi bölümün görüntüsü alınacak (0-3).
			_shot_level = int(arg.substr(13))
			_shot_level_set = true
		elif arg.begins_with("--shot-x="):
			## Oyuncunun X konumu.
			_shot_x = float(arg.substr(9))
			_shot_x_set = true
		elif arg.begins_with("--shot-yaw="):
			## Kameranın yaw'u (derece) — karakter yönü testi için.
			_shot_yaw = deg_to_rad(float(arg.substr(11)))
			_shot_yaw_set = true
		elif arg == "--shot-walk":
			## Karakter yürürken görüntü al (yön doğrulaması).
			_shot_walk = true
		elif arg == "--shot-prologue":
			## Prologue ekraninin goruntusu (baslatma akisi kaniti).
			_shot_prologue = true


func _process(_delta: float) -> void:
	## Otomatik çekim kapalıysa hiçbir şey yapma.
	##
	## ÖLÇÜLEN HATA: `--shot-prologue` modunda `_auto_shot_enabled = false`
	## yapılıyordu AMA `_process` bu bayrağı KONTROL ETMİYORDU → 150.
	## karede (~2.5 sn) görüntü alıp oyunu kapatıyordu. Prologue'un
	## 17 sn'lik akışı (buton 10 sn'de beliriyor) hiç tamamlanamıyordu.
	if not _auto_shot_enabled:
		return
	if _auto_shot_path == "" or _auto_shot_frame >= _auto_shot_target:
		return
	_auto_shot_frame += 1
	if _auto_shot_frame == _auto_shot_target:
		save_shot(_auto_shot_path)
		await get_tree().create_timer(1.2).timeout
		get_tree().quit()


## ── EKRAN GÖRÜNTÜSÜ (geliştirme aracı) ─────────────────────────────────────
## Oyun içinden PNG kaydeder. Geliştirici konsolundan:
##   get_tree().root.get_node("Main").save_shot("res://shot.png")
func save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img:
		var err: int = img.save_png(path)
		print("GÖRÜNTÜ KAYDEDİLDİ: ", path, " hata=", err)


## ── OYUN SONU ───────────────────────────────────────────────────────────────
func _on_game_ended(reason: GameManager.EndReason, final_score: int) -> void:
	## Son ekranı göster; UI zaten mesajı yazdı.
	## Burada ileride: mutlu son → aile fotoğrafı; komik son → krem efekti.
	match reason:
		GameManager.EndReason.ARRIVED:
			## "İYİ Kİ DOĞDUN DERİN!" — aile tablosu + konfeti + replik.
			final_screen.call("show_final", final_score, game.time_left)
		GameManager.EndReason.CAKE_DROPPED:
			## "PASTA DÜŞTÜ!" — kremaya bulanmış pasta efekti.
			final_screen.call("show_comedy")
		GameManager.EndReason.TIME_UP:
			## "SÜRE BİTTİ!" — Derin telefonu açıyor.
			final_screen.call("show_timeout")
