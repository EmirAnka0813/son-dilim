extends Control
##
## FİNAL EKRANI — "İYİ Kİ DOĞDUN DERİN!"
## ============================================================================
## Zamanında eve gelindiğinde açılan mutlu son ekranı.
##
## ── TASARIM: "İYİ Kİ DOĞDUN DERİN!" DETAYI ─────────────────────────────────
## Hikâyenin duygusal doruğu. Derin (kardeş) 10 yaşına giriyor; büyük abi
## pasta ve hediyeyi zamanında getirdi.
##
## EKRAN DÜZENİ (1280×720):
##
##   ┌────────────────────────────────────────────────────────┐
##   │            ✦  SON DİLİM  ✦                            │  ← üst bant
##   │                                                        │
##   │    ┌──────────┐                                       │
##   │    │ DERİN    │      "İYİ Kİ DOĞDUN DERİN!"           │  ← başlık (altın)
##   │    │ fotoğraf │      "Pastayı zamanında getirdin.       │
##   │    │ çerçeve │       Mumları üflemeye hazırız."        │
##   │    └──────────┘                                       │
##   │                                                        │
##   │   ┌────┐ ┌────┐ ┌────┐ ┌────┐   ← aile fotoğraf şeridi │
##   │   │    │ │    │ │    │ │    │      (4 kare, sıcak ışık) │
##   │   └────┘ └────┘ └────┘ └────┘                        │
##   │                                                        │
##   │        SKOR 1250   ·   SÜRE 14:32   ·   +300          │  ← istatistik
##   │                                                        │
##   │           [TEKRAR OYNA]  [ANA MENÜ]                   │
##   └────────────────────────────────────────────────────────┘
##
## ── "İYİ Kİ DOĞDUN" METNİNİN KONUMLANDIRILMASI ──────────────────────────
## 1) EKRANDA: Altın (#FFD24A) gradient, 52px, hafif harf aralığı, üstünde
##    ince altın çizgi. Arkasında radyal altın parıltı (RadialGradient).
##    Ekranda görünür konum: üst 1/3'ün ortası.
##
## 2) DÜNYADA (3B): Mutlu son sahnesinde, evin kapısının üstünde
##    Neon tabela şeklinde "İYİ Kİ DOĞDUN!" yazısı. Camera bu tabelaya
##    doğru yumuşakça döner, tabela hafifçe titrer (neon flicker).
##
## 3) PANKART: Oyun sonu ekranında Derin'in fotoğrafının ALTINDA, yazı
##    kutucuğunda ("Abla pasta getirdi mi? Annem diyor ki getiriyormus :D").
##    Fotoğraf + metin = kişisel dokunuş.
##
## 4) SES: "success.wav" (yükselen arpej) + alkış sesi (ayrı dosya).
##
## 5) DERİN'İN SESLİ REPLİĞİ: Ekran açılınca alt kısımda konuşma balonu
##    belirir: "Abi, pastayı getirdin mi? Ben burada bekliyordum!"
## ============================================================================

## Fotoğraf dosyaları (res/assets/photos/).
const PHOTOS: Array[String] = [
	"res://res/assets/photos/derin_1.jpg",
	"res://res/assets/photos/derin_2.jpg",
	"res://res/assets/photos/derin_3.jpg",
	"res://res/assets/photos/derin_4.jpg",
]

## Aile tablosu isimleri (aile fotoğrafının altındaki etiketler).
const FAMILY_LABELS: Array[String] = ["DERİN", "Abla", "Anne", "Baba"]

## Derin'in repliği (konuşma balonu).
const DERIN_LINE: String = "Abi, pastayı getirdin mi? Ben burada bekliyordum!"

@onready var title_label: Label = $Content/TitleLabel
@onready var subtitle_label: Label = $Content/SubtitleLabel
@onready var bubble: PanelContainer = $Content/Bubble
@onready var bubble_label: Label = $Content/Bubble/BubbleLabel
@onready var family_row: HBoxContainer = $Content/FamilyRow
@onready var score_value: Label = $Content/Stats/ScoreValue
@onready var time_value: Label = $Content/Stats/TimeValue
@onready var confetti: Control = $Confetti

var _score: int = 0
var _time_left: float = 0.0
var _tween: Tween = null


func _ready() -> void:
	_apply_arcade_font()
	_build_family_photos()
	_build_confetti()
	bubble_label.text = DERIN_LINE
	## Başlıkta hafif harf aralığı (sinematik).
	title_label.add_theme_constant_override("outline_size", 10)


## Arcade fontu uygula (varsa).
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


## ── AİLE FOTOĞRAF ŞERİDİ ──────────────────────────────────────────────────
func _build_family_photos() -> void:
	for child in family_row.get_children():
		child.queue_free()
	for i in 4:
		var slot := VBoxContainer.new()
		slot.custom_minimum_size = Vector2(130, 0)
		slot.alignment = BoxContainer.ALIGNMENT_CENTER

		## Fotoğraf (yuvarlak çerçeve).
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(118, 118)
		frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.10, 0.22)
		style.border_color = Color(1.0, 0.82, 0.29, 0.85)
		style.set_border_width_all(3)
		style.set_corner_radius_all(59)
		frame.add_theme_stylebox_override("panel", style)

		var photo := TextureRect.new()
		photo.custom_minimum_size = Vector2(106, 106)
		photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		photo.texture = _load_photo(PHOTOS[i])
		frame.add_child(photo)
		slot.add_child(frame)

		## İsim etiketi.
		var label := Label.new()
		label.text = FAMILY_LABELS[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
		slot.add_child(label)

		family_row.add_child(slot)


## Fotoğrafı yükle (yoksa boş kalır — oyun bozulmaz).
func _load_photo(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


## ── KONFETİ (mutlu son efekti) ─────────────────────────────────────────────
## Basit 2D parçacık sistemi — 3D partikül yerine hafif ve ucuz.
func _build_confetti() -> void:
	for i in 40:
		var piece := ColorRect.new()
		piece.color = Color.from_hsv(randf(), 0.75, 0.95)
		piece.size = Vector2(randf_range(5, 11), randf_range(8, 16))
		piece.position = Vector2(randf_range(0, 1280), randf_range(-200, 0))
		piece.rotation = randf() * TAU
		confetti.add_child(piece)
		## Her parçacık kendi düşüş animasyonunu yapar.
		var tween := create_tween().set_loops()
		var delay: float = randf_range(0.0, 2.5)
		var fall_time: float = randf_range(2.2, 4.5)
		tween.tween_interval(delay)
		tween.tween_property(piece, "position:y", 780.0, fall_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(piece, "rotation",
			piece.rotation + TAU * 3.0, fall_time)
		tween.tween_property(piece, "position:y", -200.0, 0.1)
		tween.tween_callback(func() -> void:
			piece.position.x = randf_range(0, 1280))


## ── EKRANI AÇ ──────────────────────────────────────────────────────────────
func show_final(score: int, time_left: float) -> void:
	_score = score
	_time_left = time_left
	visible = true

	## İstatistikler.
	score_value.text = str(score)
	var minutes: int = int(time_left) / 60
	var seconds: int = int(time_left) % 60
	time_value.text = "%02d:%02d" % [minutes, seconds]

	## Başlık animasyonu — harf harf belirir.
	_animate_title()

	## Konuşma balonu 1.2 sn sonra belirir.
	bubble.modulate.a = 0.0
	var bt := create_tween()
	bt.tween_interval(1.2)
	bt.tween_property(bubble, "modulate:a", 1.0, 0.4)

	## Aile fotoğrafları kademeli belirir.
	var children := family_row.get_children()
	for i in children.size():
		var slot: Control = children[i]
		slot.modulate.a = 0.0
		var st := create_tween()
		st.tween_interval(0.35 + i * 0.16)
		st.tween_property(slot, "modulate:a", 1.0, 0.35)


## Başlık "pop" animasyonu + parıltı.
func _animate_title() -> void:
	title_label.scale = Vector2(0.7, 0.7)
	title_label.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(title_label, "modulate:a", 1.0, 0.3)
	t.parallel().tween_property(title_label, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	## Altın parıltı: hafif titreşim.
	var glow := create_tween().set_loops()
	glow.tween_property(title_label, "modulate",
		Color(1.15, 1.05, 0.75), 1.4)
	glow.tween_property(title_label, "modulate", Color(1, 1, 1), 1.4)


## ── KOMEDİ FINAL (pasta düştü) ─────────────────────────────────────────────
## Kremaya bulanmış pasta + Derin'in gülümsemesi.
func show_comedy() -> void:
	visible = true
	title_label.text = "PASTA DÜŞTÜ!"
	title_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	subtitle_label.text = "Ama Derin: «Bari pastanın üzerine bir mum dikelim, böyle de yeriz!»"
	bubble_label.text = "Abi, bari pastanın üzerine bir mum dikelim, böyle de yeriz! 😄"
	## Krem efekti (ekranda).
	for i in 24:
		var blob := ColorRect.new()
		blob.color = Color(1.0, 0.96, 0.98, 0.85)
		blob.size = Vector2(randf_range(30, 120), randf_range(20, 90))
		blob.position = Vector2(randf_range(0, 1200), randf_range(0, 600))
		blob.rotation = randf() * TAU
		confetti.add_child(blob)
	bubble.modulate.a = 0.0
	var bt := create_tween()
	bt.tween_interval(0.8)
	bt.tween_property(bubble, "modulate:a", 1.0, 0.4)


## ── SÜRE BİTTİ ─────────────────────────────────────────────────────────────
func show_timeout() -> void:
	visible = true
	title_label.text = "SÜRE BİTTİ!"
	title_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30))
	subtitle_label.text = "Derin telefonu açtı: «Abla? Pastayı getirdin mi?»"
	bubble_label.text = "Abi? Pastayı getirdin mi? Telefonu açtım, sesin gidiyor..."
	bubble.modulate.a = 0.0
	var bt := create_tween()
	bt.tween_interval(0.8)
	bt.tween_property(bubble, "modulate:a", 1.0, 0.4)
