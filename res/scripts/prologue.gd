extends CanvasLayer
##
## PROLOGUE — "Pastayı ve hediyeyi alıp hemen eve gel!"
##
## NOT: Bu node CanvasLayer'dir (UI'in ÜSTÜNDE görünsün diye — layer=2).
## CanvasLayer'ın `visible` / `modulate` ÖZELLİĞİ YOKTUR; bunlar
## altındaki `PhoneScreen` Control'ü üzerinden yönetilir.
## Ayrıca CanvasLayer `set_anchors_preset` gibi Control API'lerine
## SAHİP DEĞİLDİR — buton konumu `position`/`size` ile ayarlanır.
## ============================================================================
## Oyunun açılışı. Anneden gelen SMS ile başlar:
##
##   MUTLU  │ Pastayı ve hediyeyi alıp hemen eve gel! Misafirler geldi,
##           │ Derin mumları üfleyecek!
##   MUTLU  │ Kaç dakikan var? Hemen eve gel!
##
## Sonra Derin'in sesi (telefonda):
##   DERİN  │ Abi? Ben burada bekliyorum!
##
## ── SAYFA DÖNÜŞÜMÜ (gerçek telefon ekranı hissi) ───────────────────────
##   1. Ekran kararı → telefon titreşimi (shake) + SMS bildirim sesi
##   2. Bildirim yukarıdan kayarak girer
##   3. Kullanıcı ekrana dokununca SMS uygulaması açılır
##   4. Mesajlar tek tek belirir (yazıyor efekti ile)
##   5. "BAŞLA" butonu aktifleşir
##
## ── "İYİ Kİ DOĞDUN DERİN!" DETAYI ────────────────────────────────────────
## Prologue'da Derin'in fotoğrafı küçük bir avatar olarak SMS konuşma
## balonlarında görünür — hikâyenin ana kahramanı oyunun başından itibaren
## mevcut. Daha sonra FinalScreen'de büyük aile tablosunda belirir.
## ============================================================================

## Bölüm anahtarları → SMS metni.
const SMS_MESSAGES: Array[Dictionary] = [
	{"from": "MUTLU", "text": "Pastayı ve hediyeyi alıp hemen eve gel! Misafirler geldi, Derin mumları üfleyecek!", "color": Color(0.35, 0.75, 1.0)},
	{"from": "MUTLU", "text": "Kaç dakikan var? Hemen eve gel!", "color": Color(0.35, 0.75, 1.0)},
	{"from": "DERİN", "text": "Abi? Ben burada bekliyordum! Pasta getirdin mi?", "color": Color(1.0, 0.55, 0.80)},
]

## NOT: Bu node artık bir CanvasLayer (UI'in ÜSTÜNDE görünsün diye).
## CanvasLayer'da `visible` / `modulate` YOKTUR — bunlar PhoneScreen
## (Control) üzerinden yönetilir.
@onready var phone_screen: Control = $PhoneScreen
@onready var notification: PanelContainer = $PhoneScreen/Notification
@onready var notif_from: Label = $PhoneScreen/Notification/Header/FromLabel
@onready var notif_text: Label = $PhoneScreen/Notification/TextLabel
@onready var notif_avatar: TextureRect = $PhoneScreen/Notification/Header/Avatar
@onready var chat_app: Control = $PhoneScreen/ChatApp
@onready var chat_list: VBoxContainer = $PhoneScreen/ChatApp/Scroll/MessageList
## StartButton / TitleLabel / SubtitleLabel PhoneScreen (Control) altında —
## CanvasLayer'ın Control cocuklarında anchor calismaz, bu yuzden hepsi
## tek bir Control icinde toplandı.
@onready var start_button: Button = $PhoneScreen/StartButton
@onready var tap_hint: Label = $PhoneScreen/TapHint
@onready var title_label: Label = $PhoneScreen/TitleLabel
@onready var subtitle_label: Label = $PhoneScreen/SubtitleLabel

var _stage: int = 0
var _typing: bool = false
var _typing_tween: Tween = null
## Butona iki kez basılmasını engelle.
var _starting: bool = false
## Akış başladı mı? (çift başlatmayı önler)
var _started: bool = false
## Otomatik akış zamanlayıcısı.
var _auto_timer: SceneTreeTimer = null
## Geçen süre (saniye) — akış sayacı.
var _elapsed: float = 0.0
## Sohbet uygulaması açıldı mı?
var _chat_opened: bool = false
## Buton KESİN olarak görünecek süre (saniye). Ne olursa olsun.
const BUTON_GARANTI_SURE: float = 10.0
## Garanti buton zamanlayıcısı.
var _guarantee_timer: SceneTreeTimer = null
## Son mesajdan sonra buton zamanlayıcısı.
var _finish_timer: SceneTreeTimer = null
## Prologue'un bitip bitmediği (çift çağrı koruması).
var _finished: bool = false


func _ready() -> void:
	## TESHIS: _ready cagrildi mi?
	_diag("_ready cagrildi")
	_apply_arcade_font()
	## Buton BAŞTA görünmez ve pasif — mesajlar bitince aktifleşir.
	## (visible=false iken pressed bağlantısı da tetiklenmez.)
	start_button.disabled = true
	start_button.visible = false
	## Yine de bağlantıyı kur (kod üzerinden de tetiklenebilsin).
	if not start_button.pressed.is_connected(_on_start_pressed):
		start_button.pressed.connect(_on_start_pressed)
	## Fotoğraf avatarı.
	_load_avatar(notif_avatar)
	##
	## NOT: Akış BURADA başlatılmıyor. CanvasLayer'in `_ready`'si build'de
	## güvenilir çağrılmıyordu (teşhis: "_ready cagrildi" bile yok).
	## Main, `start_prologue()` public metodunu kendi `_ready`'sinden
	## çağırır — orada akış başlar.
	##
	## (Ayrıca çift başlatmayı önler: hem _ready hem Main çağırmasın.)


## TESHIS YAZICI (build'de print gorunmez, dosyaya yazar).
##
## NOT: READ_WRITE modu dosya YOKSA null döner → ilk çağrıda dosya
## oluşmaz ve teşhis kaybolur. Bu yüzden önce WRITE ile açıp kapat,
## sonra READ_WRITE ile ekle.
func _diag(msg: String) -> void:
	var path: String = "user://prologue_diag.txt"
	if not FileAccess.file_exists(path):
		var f0 := FileAccess.open(path, FileAccess.WRITE)
		if f0 != null:
			f0.store_line(msg)
			f0.close()
			return
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(msg)
	f.close()


## ── PROLOGUE AKIŞI ────────────────────────────────────────────────────────
##
## PUBLIC BAŞLATMA — Main bu metodu çağırır.
##
## ÖLÇÜLEN HATA: CanvasLayer'in `_ready()`'si build'de güvenilir ÇAĞRILMIYORDU
## (teşhis dosyasında "_ready cagrildi" yazısı bile yok). CanvasLayer bir
## CanvasItem DEĞİLDİR — `_ready` sıralaması farklı çalışabiliyor.
##
## Çözüm: Main, akışı DİREKT bu public metotla başlatır. Main'in
## `_ready`'si her zaman çalışır (Node3D → normal CanvasItem sıralaması).
func start_prologue() -> void:
	_diag("start_prologue cagrildi")
	_start()


func _start() -> void:
	## Çift başlatmayı önle.
	if _started:
		return
	_started = true
	_diag("_start cagrildi")
	## ── GÜVENLİK AĞI (EN ÖNCE, await ÖNCESİ) ──
	## Hiçbir koşulda, 14 saniye sonra buton kesinlikle görünecek.
	## Bu, "takılma" hissini KESİN olarak ortadan kaldırır.
	##
	## ÖNEMLİ: Bu çağrı await'ten ÖNCE olmalı. _start() coroutine'dir;
	## bir await'ten sonra kalan satırlar o await tamamlanana kadar
	## ÇALIŞMAZ. (Ölçülen hata: "_guarantee_button basladi" hiç yazılmadı.)
	_guarantee_button(14.0)

	## 1) Ekran kararı: telefon titreşimi.
	phone_screen.modulate = Color(0, 0, 0, 1)
	var t := create_tween()
	t.tween_property(phone_screen, "modulate", Color(1, 1, 1, 1), 0.5)
	## Titreşim (SMS geldi).
	_vibrate(0.35)
	## 2) Bildirim yukarıdan kayarak girer.
	notification.position.y = -220.0
	notification.modulate.a = 0.0
	var n := create_tween()
	n.set_parallel(true)
	n.tween_property(notification, "position:y", 0.0, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	n.tween_property(notification, "modulate:a", 1.0, 0.3)
	## 3) İlk mesaj gösterilir.
	notif_from.text = SMS_MESSAGES[0]["from"]
	notif_text.text = SMS_MESSAGES[0]["text"]
	notif_from.add_theme_color_override("font_color", SMS_MESSAGES[0]["color"])
	## 4) 2 saniye sonra chat uygulaması açılır.
	##
	## ÖNEMLİ: await KULLANILMAZ. _start() bir coroutine olursa, await'ten
	## SONRAKİ satırlar o await tamamlanana kadar çalışmaz.
	var c: SceneTreeTimer = get_tree().create_timer(2.2)
	c.timeout.connect(_on_chat_timer)
	## 5) Kullanıcı hiçbir şeye tıklamazsa bile mesajlar otomatik akar.
	_schedule_auto_next(5.0)


## Chat timer'ı tetiklendi → sohbeti aç.
func _on_chat_timer() -> void:
	if _starting or _finished:
		return
	if not chat_app.visible:
		_open_chat()


## GÜVENLİK AĞI: N saniye sonra buton KESIN görünür olur.
## Hangi yol çalışırsa çalışsın (tween iptal olsa, timer kaybolsa)
## oyun başlatılabilir duruma gelmek garanti.
func _guarantee_button(delay: float) -> void:
	## NOT: await KULLANILMAZ — await, çağıran fonksiyonu coroutine yapar
	## ve akışı bozar (ölçülen hata: buton hiç görünmedi).
	_guarantee_timer = get_tree().create_timer(delay)
	_guarantee_timer.timeout.connect(_on_guarantee_timeout)


## Garanti timer'ı tetiklendi → butonu göster.
func _on_guarantee_timeout() -> void:
	if not _finished:
		_finish_prologue()


## Chat uygulamasını aç (mesajlar tek tek).
func _open_chat() -> void:
	notification.visible = false
	chat_app.visible = true
	chat_app.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(chat_app, "modulate:a", 1.0, 0.35)
	tap_hint.visible = true
	## İpucu: hem tıklayarak hem bekleyerek ilerlenebilir.
	tap_hint.text = "Mesajlar otomatik gelecek — istersen ekrana dokun"
	## İlk mesajı sayac yönetir (_run_countdown_flow).
	_stage = 0


## Sonraki mesajı göster (kullanıcı dokununca VEYA otomatik akış).
func _advance_chat() -> void:
	if _stage >= SMS_MESSAGES.size():
		if not _finished:
			_finish_prologue()
		return
	_add_message(_stage, 0.25)
	_stage += 1
	if _stage >= SMS_MESSAGES.size():
		## Son mesaj yazılınca buton belirsin (1.8 sn sonra).
		_finish_timer = get_tree().create_timer(1.8)
		_finish_timer.timeout.connect(_on_finish_timeout)
	else:
		## Sonraki mesajı otomatik getir.
		_schedule_auto_next(2.4)


## Otomatik akış: kullanıcı beklemez.
##
## NEDEN TIMER, TWEEN DEĞİL: Tween, node görünmez olduğunda veya sahne
## değiştiğinde otomatik iptal olabiliyor. Timer (get_tree().create_timer)
## sahne ağacından bağımsız çalışır ve asla "kaybolmaz".
func _schedule_auto_next(delay: float) -> void:
	## Timer BAĞLANTISI (await değil).
	_auto_timer = get_tree().create_timer(delay)
	_auto_timer.timeout.connect(_auto_advance)


## Otomatik ilerleme — kullanıcı hiç tıklamazsa da mesajlar akar.
func _auto_advance() -> void:
	if _starting or _finished:
		return
	if not is_inside_tree():
		return
	if not phone_screen.visible:
		return
	if chat_app.visible:
		_advance_chat()
	elif notification.visible:
		## Bildirim sonrası chat açılmadı — aç.
		_open_chat()


## Bir mesaj balonu ekle (yazıyor efekti ile).
func _add_message(index: int, delay: float) -> void:
	var data: Dictionary = SMS_MESSAGES[index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	## Avatar (sadece Derin'in mesajında).
	var is_derin: bool = data["from"] == "DERİN"
	if is_derin:
		var av := TextureRect.new()
		av.custom_minimum_size = Vector2(34, 34)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_load_avatar(av)
		row.add_child(av)

	## Balon.
	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.20, 0.30) if not is_derin else Color(0.32, 0.14, 0.26)
	style.set_corner_radius_all(16)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	bubble.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	bubble.add_child(vbox)

	var from_label := Label.new()
	from_label.text = data["from"]
	from_label.add_theme_font_size_override("font_size", 13)
	from_label.add_theme_color_override("font_color", data["color"])
	vbox.add_child(from_label)

	var text_label := Label.new()
	text_label.add_theme_font_size_override("font_size", 16)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.text = ""
	vbox.add_child(text_label)

	row.add_child(bubble)
	chat_list.add_child(row)

	## Yazıyor efekti: harf harf.
	_type_text(text_label, data["text"], delay)


## Harf harf yazdırma efekti.
func _type_text(label: Label, full_text: String, delay: float) -> void:
	if _typing:
		return
	_typing = true
	## Not: GDScript'te çok argümanlı tween_method çağrısında lambda bloğu
	## virgülle ayrılamaz — bu yüzden tween'i adım adım kuruyoruz.
	var t := create_tween()
	t.tween_interval(delay)
	var counter: int = 0
	var total: int = full_text.length()
	t.tween_method(_set_text_partial.bind(label, full_text), 0, total, 0.018)
	t.tween_callback(func() -> void: _typing = false)


## tween_method için: metnin ilk N karakterini yazar.
func _set_text_partial(value: int, label: Label, full_text: String) -> void:
	label.text = full_text.substr(0, value)
	if value >= full_text.length():
		label.text = full_text


## Prologue bitti → oyun başlar.
func _finish_prologue() -> void:
	## Çift çağrı koruması.
	if _finished:
		return
	_finished = true
	tap_hint.visible = false
	## Butonu netlestir.
	start_button.text = "BAŞLA →"
	title_label.text = "SON DİLİM"
	subtitle_label.text = "Derin'in pastasını eve götür"
	title_label.visible = true
	subtitle_label.visible = true
	start_button.visible = true
	start_button.disabled = false
	_diag("finished=1 btn_visible=%s btn_pos=%s btn_size=%s vp=%s"
		% [str(start_button.visible), str(start_button.position),
		str(start_button.size), str(get_viewport().get_visible_rect().size)])
	print("PROLOGUE: BAŞLA butonu görünür oldu")
	## Buton HER ZAMAN en üstte (prologue ekranının en üstü).
	start_button.z_index = 100
	title_label.z_index = 100
	subtitle_label.z_index = 100
	## Butonu EKRANIN ALT ORTASINA sabitle — layout dosyasındaki
	## anchor'lar bazen 0 boyutlu kalabiliyor. Elle konumlandır.
	## CanvasLayer'da get_viewport_rect() YOK (Control'e özel).
	## get_viewport().get_visible_rect() her iki durumda da çalışır.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	start_button.custom_minimum_size = Vector2(300, 72)
	start_button.size = Vector2(300, 72)
	start_button.offset_right = 300.0
	start_button.offset_bottom = 72.0
	## Konum: ekran YÜZDESİ değil, MUTLAK piksel olarak hesapla.
	## 720p ekranda buton y=560 (altta, görünür), 1080p'de y=880.
	## Ekrandan 120 piksel yukarıda dur.
	var btn_y: float = maxf(vp.y - 150.0, 200.0)
	start_button.position = Vector2((vp.x - 300.0) * 0.5, btn_y)
	start_button.pivot_offset = start_button.size * 0.5
	## Başlık + buton birlikte okunsun diye başlığı da ortala.
	## Başlık butonun 260 piksel üstünde.
	##
	## NOT: CanvasLayer'da Control cocuklarının anchor'ı çalışmaz —
	## `position` doğrudan CanvasLayer koordinatıdır. Bu yüzden
	## "size" yerine "offset_right/bottom" da gerekebilir; en güvenlisi
	## hem size hem offset ayarlamak.
	var title_y: float = maxf(btn_y - 260.0, 60.0)
	title_label.size = Vector2(vp.x, 60)
	title_label.position = Vector2(0, title_y)
	title_label.offset_right = vp.x
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.size = Vector2(vp.x, 40)
	subtitle_label.position = Vector2(0, title_y + 62)
	subtitle_label.offset_right = vp.x
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	print("PROLOGUE: buton pos=%s size=%s vp=%s" %
		[start_button.position, start_button.size, vp])
	## Buton "pop" animasyonu.
	start_button.scale = Vector2(0.6, 0.6)
	start_button.pivot_offset = start_button.size * 0.5
	var t := create_tween()
	t.tween_property(start_button, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	## Başlık yazıyor.
	title_label.modulate.a = 0.0
	var t2 := create_tween()
	t2.tween_property(title_label, "modulate:a", 1.0, 0.4)
	t2.tween_property(subtitle_label, "modulate:a", 1.0, 0.4)


## Başla butonuna basıldı → oyunu başlat.
func _on_start_pressed() -> void:
	## Çift tetiklemeyi engelle.
	if _starting:
		return
	_starting = true
	## Prologue'u hemen gizle — oyun başlaması BEKLETMEMELİ.
	## (Eski davranış: 0.4sn fade + tween callback. Butona basıldıktan
	## sonra ekran donuyor gibi görünüyordu.)
	##
	## NOT: Bu node CanvasLayer → `visible` YOK. Altındaki Control'ün
	## (PhoneScreen) görünürlüğünü kapatıyoruz.
	phone_screen.visible = false
	phone_screen.modulate.a = 1.0
	## Oyunu başlat.
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		push_error("Prologue: Main bulunamadi!")
		return
	if not main.has_method("begin_game"):
		push_error("Prologue: begin_game bulunamadi!")
		return
	main.call("begin_game")


## Buton ve başlıkları her karede konumlandır.
##
## NEDEN: CanvasLayer içindeki Control'lerin anchor'ı güvenilir çalışmaz
## ve pencere yeniden boyutlandığında konum bozulur. Her karede mutlak
## piksel konumu atamak en sağlam yöntem — buton HER ZAMAN ekranda ve
## tıklanabilir olur.
func _process(delta: float) -> void:
	## TESHIS: her 2 saniyede sayaç + durum bilgisi yaz.
	if fmod(_elapsed, 2.0) < delta:
		_diag("t=%.1f elapsed=%.2f starting=%s finished=%s chat_opened=%s stage=%d phone_vis=%s"
			% [_elapsed, _elapsed, str(_starting), str(_finished),
			str(_chat_opened), _stage, str(phone_screen.visible)])
	## ── GERİ SAYIM TABANLI AKIŞ ──
	##
	## SceneTreeTimer'lar bu sahnede TETİKLENMİYORDU (teşhis dosyası:
	## "_ready cagrildi" yazıldı ama "_finish_prologue" hiç çağrılmadı).
	## Nedeni: CanvasLayer + process_mode zinciri. Çözüm: TEK SAYAÇ.
	## _process her karede çalışır (CanvasLayer'da da çalışır) ve tüm
	## akış bu sayaca bağlıdır — hiçbir zamanlayıcıya güvenilmez.
	if not _starting:
		_elapsed += delta
		_run_countdown_flow()

	if _starting or not phone_screen.visible:
		return
	if not start_button.visible:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x < 10.0 or vp.y < 10.0:
		return
	var btn_y: float = maxf(vp.y - 150.0, 200.0)
	start_button.size = Vector2(300, 72)
	start_button.position = Vector2((vp.x - 300.0) * 0.5, btn_y)
	var title_y: float = maxf(btn_y - 260.0, 60.0)
	title_label.size = Vector2(vp.x, 60)
	title_label.position = Vector2(0, title_y)
	subtitle_label.size = Vector2(vp.x, 40)
	subtitle_label.position = Vector2(0, title_y + 62)


## Son-mesaj timer'ı tetiklendi → butonu göster.
func _on_finish_timeout() -> void:
	if not _finished:
		_finish_prologue()


## Sayaca bağlı Prologue akışı.
##
## ZAMAN ÇİZELGESİ:
##   0.0 sn  → bildirim görünür (SMS geldi)
##   2.2 sn  → sohbet uygulaması açılır, 1. mesaj yazılır
##   4.8 sn  → 2. mesaj
##   7.2 sn  → 3. mesaj (Derin)
##  10.0 sn  → BAŞLA butonu kesin görünür
##
## Kullanıcı isterse ekrana dokunarak mesajları erken ilerletebilir —
## ama hiçbir şeye dokunmasa da akış tamamlanır.
func _run_countdown_flow() -> void:
	## 2.2 sn: sohbeti aç ve ilk mesajı göster.
	if _elapsed >= 2.2 and not _chat_opened:
		_chat_opened = true
		_open_chat()
		return

	## Mesajlar 2.6 sn arayla gelsin. want_index 0 → ilk mesaj (2.2 sn).
	var want_index: int = int((_elapsed - 2.2) / 2.6)
	if _chat_opened and want_index >= _stage and _stage < SMS_MESSAGES.size():
		_add_message(_stage, 0.25)
		_stage += 1
		if _stage >= SMS_MESSAGES.size():
			## Son mesaj yazıldı — buton hemen hazır olsun.
			if not _finished:
				_finish_prologue()
			return

	## 10 sn: ne olursa olsun buton görünür.
	if _elapsed >= BUTON_GARANTI_SURE and not _finished:
		_finish_prologue()


## ── YARDIMCI ───────────────────────────────────────────────────────────────
## Telefon titreşimi.
func _vibrate(duration: float) -> void:
	var t := create_tween()
	t.set_loops(int(duration / 0.06))
	for i in 6:
		t.tween_property(phone_screen, "position",
			Vector2(randf_range(-4, 4), randf_range(-4, 4)), 0.03)
		t.tween_property(phone_screen, "position", Vector2.ZERO, 0.03)


## Avatar fotoğrafını yükle.
func _load_avatar(rect: TextureRect) -> void:
	for i in range(1, 5):
		var path: String = "res://res/assets/photos/derin_%d.jpg" % i
		if ResourceLoader.exists(path):
			rect.texture = load(path)
			return


## Arcade font.
func _apply_arcade_font() -> void:
	var font_path: String = "res://res/fonts/ArcadeFont.ttf"
	if not ResourceLoader.exists(font_path):
		return
	var font: Font = load(font_path)
	if font == null:
		return
	for node in _collect_labels(self):
		node.add_theme_font_override("font", font)


func _collect_labels(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in node.get_children():
		if child is Label or child is Button:
			result.append(child)
		result.append_array(_collect_labels(child))
	return result


func _input(event: InputEvent) -> void:
	## Chat açıkken ekrana dokununca sonraki mesaj.
	if chat_app.visible and _input_tap(event):
		_advance_chat()


func _input_tap(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return false
