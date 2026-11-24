extends CanvasLayer
class_name UIController
##
## ARAYÜZ DENETLEYİCİSİ — kronometre, pasta denge barı, ekran mesajları
## ============================================================================
## Bu düğüm Main.tscn içinde UI adıyla bulunur ve şu çocukları barındırır:
##
##   TimerLabel    Label    — "02:00" biçiminde geri sayan kronometre
##   BalanceBar    ProgressBar — pasta denge çubuğu (0..100, 50 = düz)
##   BalanceNeedle TextureRect/ColorRect — çubuğun üstündeki ibre
##   SlipBar       ProgressBar — krem kayma miktarı (0..100)
##   MessageLabel  Label    — ortadaki büyük mesaj ("PASTA DÜŞTÜ!")
##   LevelLabel    Label    — sol üstte bölüm adı
##   ScoreLabel    Label    — skor
##
## ── DENGE BARI MANTIĞI (adım adım) ────────────────────────────────────────
## 1) Her karede balance.balance_changed sinyali gelir (angle, slip).
## 2) angle → normalize edilir:
##        ratio = angle / max_manual_tilt     →  [-1..1]
##        Değer 50 (ortadaki) değilse çubuk ibresi kayar.
##    get_tilt_ratio() bu normalize işlemi yapar.
## 3) ratio → ekran pikseli:
##        x = 50% + ratio * 45%     (merkezden %45 sapma)
##    Böylece ibre ekranın kenarlarına kadar gidebilir ama asla taşmaz.
## 4) slip → renk:
##        slip < 0.35  → yeşil (güvenli)
##        slip < 0.70  → sarı (dikkat)
##        slip >= 0.70 → kırmızı (tehlike, ekran titrer)
## 5) Eğim çubuğu çubuğun ÜSTÜNDE, krem çubuğu ALTINDA olacak şekilde
##    yerleştirilir — oyuncu iki bilgiyi aynı anda görür:
##    "kutu ne kadar eğik" + "krem ne kadar kaçmış".
## ============================================================================

## ── SAHNE REFERANSLARI ─────────────────────────────────────────────────────
@onready var timer_label: Label = $TimerPanel/TimerLabel
@onready var balance_bar: ProgressBar = $BalancePanel/BalanceBar
@onready var balance_needle: Control = $BalancePanel/BalanceNeedle
@onready var balance_hint: Label = $BalancePanel/BalanceHint
@onready var slip_bar: ProgressBar = $BalancePanel/SlipBar
@onready var slip_label: Label = $BalancePanel/SlipLabel
@onready var message_label: Label = $CenterMessage
@onready var level_label: Label = $TopLeft/LevelLabel
@onready var score_label: Label = $TopLeft/ScoreLabel
@onready var hint_label: Label = $BottomHint

## Denge çubuğunda "güvenli" bölgenin genişliği (yüzde).
@export var safe_zone_percent: float = 46.0
## Ekran titremesi eşiği (krem kayma oranı).
@export var shake_threshold: float = 0.70
## Titremenin şiddeti (piksel).
@export var shake_amount: float = 6.0

var _shake_time: float = 0.0
var _message_time: float = 0.0
var _balance: CakeBalance = null
var _game: GameManager = null


func _ready() -> void:
	_apply_arcade_font()
	## Çubuk aralıkları.
	balance_bar.min_value = 0.0
	balance_bar.max_value = 100.0
	balance_bar.value = 50.0
	slip_bar.min_value = 0.0
	slip_bar.max_value = 100.0
	slip_bar.value = 0.0
	## Güvenli bölgeyi göstermek için orta çizgi.
	_update_needle(50.0)
	_center_message("", 0.0)


func bind(game: GameManager, balance: CakeBalance) -> void:
	_game = game
	_balance = balance
	if _balance:
		_balance.balance_changed.connect(_on_balance_changed)
		_balance.slip_warning.connect(_on_slip_warning)
	if _game:
		_game.time_changed.connect(_on_time_changed)
		_game.score_changed.connect(_on_score_changed)
		_game.level_changed.connect(_on_level_changed)
		_game.game_ended.connect(_on_game_ended)
		_game.state_changed.connect(_on_state_changed)


func _process(delta: float) -> void:
	## Ekran titremesi (krem tehlikeliyken).
	if _shake_time > 0.0:
		_shake_time -= delta
		var amount: float = shake_amount * clampf(_shake_time * 4.0, 0.0, 1.0)
		balance_bar.position = Vector2(
			randf_range(-amount, amount), randf_range(-amount, amount))
	elif balance_bar.position != Vector2.ZERO:
		balance_bar.position = Vector2.ZERO

	## Mesaj zaman aşımı.
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_center_message("", 0.0)


## ═══════════════════════════════════════════════════════════════════════════
## ARCADE FONT
## ═══════════════════════════════════════════════════════════════════════════
## res/fonts/ArcadeFont.ttf (Press Start 2P — SIL Open Font License).
## Varsa tüm UI metinlerine uygulanır; yoksa Godot'in varsayılan fontu kalır.
func _apply_arcade_font() -> void:
	var font_path: String = "res://res/fonts/ArcadeFont.ttf"
	if not ResourceLoader.exists(font_path):
		return
	var font: Font = load(font_path)
	if font == null:
		return
	var theme: Theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	## Mevcut tüm Label/Button'lara uygula.
	for node in _collect_labels(self):
		node.add_theme_font_override("font", font)


## Tüm alt node'lardaki Label ve Button'ları topla.
func _collect_labels(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in node.get_children():
		if child is Label or child is Button:
			result.append(child)
		result.append_array(_collect_labels(child))
	return result


## ═══════════════════════════════════════════════════════════════════════════
## SİNYAL İŞLEYİCİLERİ
## ═══════════════════════════════════════════════════════════════════════════
func _on_balance_changed(angle: float, slip: float) -> void:
	## 1) Eğim → ibre konumu.
	var tilt_ratio: float = _balance.get_tilt_ratio() if _balance else 0.0
	var needle_x: float = 50.0 + tilt_ratio * 45.0
	_update_needle(needle_x)

	## 2) Krem kayması → çubuk doluluğu.
	var slip_percent: float = slip * 100.0
	slip_bar.value = slip_percent

	## 3) Renk: güvenli / dikkat / tehlike.
	var bar_color: Color = Color(0.35, 0.85, 0.45)      # yeşil
	if slip >= 0.70:
		bar_color = Color(0.95, 0.28, 0.28)               # kırmızı
	elif slip >= 0.35:
		bar_color = Color(0.98, 0.78, 0.25)               # sarı
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bar_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slip_bar.add_theme_stylebox_override("fill", style)

	## 4) İbre rengi de tehlikeye göre değişir.
	balance_needle.modulate = bar_color

	## 5) Krem kaçıyorsa ipucu metni.
	if slip > 0.5:
		balance_hint.text = "KREM KAYIYOR! Q/E ile düzelt"
		balance_hint.modulate = bar_color
	elif absf(tilt_ratio) > 0.5:
		balance_hint.text = "Kutu çok eğik!"
		balance_hint.modulate = Color(1, 1, 1, 0.8)
	else:
		balance_hint.text = "Q / E  ·  kutuyu düz tut"
		balance_hint.modulate = Color(1, 1, 1, 0.55)


func _on_time_changed(remaining: float) -> void:
	var minutes: int = int(remaining) / 60
	var seconds: int = int(remaining) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]
	## Son 30 saniyede kırmızıya döner ve yanıp söner.
	if remaining <= 30.0:
		timer_label.modulate = Color(1.0, 0.35, 0.35)
		var blink: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
		timer_label.modulate.a = blink
	else:
		timer_label.modulate = Color(1, 1, 1, 1)


func _on_score_changed(new_score: int) -> void:
	score_label.text = "SKOR %d" % new_score


func _on_level_changed(level: int) -> void:
	var names: Array[String] = [
		"BÖLÜM 1 — OFİSTEN KAÇIŞ",
		"BÖLÜM 2 — TRAFİK CANAVARI",
		"BÖLÜM 3 — TOPLU TAŞIMA KABUSU",
		"BÖLÜM 4 — SON YOKUŞ",
	]
	if level < names.size():
		level_label.text = names[level]
	else:
		level_label.text = "FİNAL — EVE VAR!"


func _on_slip_warning() -> void:
	_shake_time = 0.35
	_center_message("PASTA KAYIYOR!", 1.2)


func _on_game_ended(reason: GameManager.EndReason, final_score: int) -> void:
	match reason:
		GameManager.EndReason.ARRIVED:
			_center_message("İYİ Kİ DOĞDUN DERİN!", 4.0)
		GameManager.EndReason.CAKE_DROPPED:
			_center_message("PASTA DÜŞTÜ!", 3.5)
		GameManager.EndReason.TIME_UP:
			_center_message("SÜRE BİTTİ!", 3.5)


func _on_state_changed(new_state: GameManager.State) -> void:
	match new_state:
		GameManager.State.PLAY:
			hint_label.visible = true
		_:
			hint_label.visible = false


## ═══════════════════════════════════════════════════════════════════════════
## YARDIMCI
## ═══════════════════════════════════════════════════════════════════════════
## İbreyi çubuk üzerinde konumlandır (yüzde 0..100).
func _update_needle(percent: float) -> void:
	## İbre, çubuğun genişliğine göre konumlanır — responsive.
	var bar_width: float = balance_bar.size.x
	balance_needle.position.x = (percent / 100.0) * bar_width - balance_needle.size.x * 0.5


## Ortada büyük mesaj göster.
func _center_message(text: String, duration: float) -> void:
	message_label.text = text
	_message_time = duration
	message_label.visible = text != ""
	if text != "":
		message_label.modulate.a = 1.0
		## Kısa bir ölçek animasyonu (punch).
		message_label.scale = Vector2(1.15, 1.15)
		var tween: Tween = create_tween()
		tween.tween_property(message_label, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
