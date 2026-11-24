extends Node
class_name GameManager
##
## OYUN YÖNETİCİSİ — zaman, bölümler, checkpoint'ler, sonuçlar
## ============================================================================
## Tek bir "beyin" (autoload). Şunları yönetir:
##   · Geri sayan kronometre (time_left)
##   · Aktif bölüm ve bölüm geçişleri
##   · Checkpoint kayıtları ve geri dönüş
##   · Oyun durumları (PROLOGUE / PLAY / WIN / LOSE)
##   · Skor ve istatistik
##
## ── ZAMAN BASKISI ───────────────────────────────────────────────────────────
## Süre azaldıkça arka plan müziğinin temposu artar. Bu, müzik motorunun
## pitch_scale'ini değiştirerek yapılır — ses dosyası değişmez, tempo değişir.
##
##     music.pitch_scale = 1.0 + (1.0 - remaining_ratio) * 0.12
##
## Son 30 saniyede ek bir "kalp atışı" darbesi eklenir (tick sesi).
## ============================================================================

## Sahne yolları (Bölüm 1'den başlar, ileride eklenir).
const LEVEL_SCENES: Array[String] = [
	"res://res/scenes/Level_Office.tscn",
	"res://res/scenes/Level_Street.tscn",
]

## Toplam süre (saniye) — 20 dakika.
@export var total_time: float = 1200.0
## Müzik hızlanmasının başlayacağı son süre (saniye).
@export var music_rush_threshold: float = 60.0

## ── DURUM ───────────────────────────────────────────────────────────────────
enum State { PROLOGUE, PLAY, WIN, LOSE }
enum EndReason { TIME_UP, CAKE_DROPPED, ARRIVED }

var state: State = State.PROLOGUE
var time_left: float = 1200.0
var score: int = 0
var end_reason: EndReason = EndReason.TIME_UP
var current_level: int = 0

## Sahnedeki oyuncu ve denge referansları.
var player: Player = null
var balance: CakeBalance = null

## Checkpoint'ler: pozisyon + alınan bölüm.
var _checkpoints: Array[Dictionary] = []
## Aktif checkpoint indeksi (-1 = henüz yok).
var _active_checkpoint: int = -1

## Müzik temposu için.
var _music: AudioStreamPlayer = null
var _tick: AudioStreamPlayer = null
var _last_tick_second: int = -1

## ── SİNYALLER ───────────────────────────────────────────────────────────────
signal time_changed(remaining: float)
signal state_changed(new_state: State)
signal score_changed(new_score: int)
signal level_changed(level: int)
signal checkpoint_reached(index: int)
signal countdown_tick(seconds_left: int)
signal game_ended(reason: EndReason, final_score: int)


func _ready() -> void:
	## Sahne içinde kullanılıyorsa gruba ekle (oyuncu sesleri bunun üzerinden
	## çağırır).
	add_to_group("game_manager")
	## Autoload olarak eklendiğinde sahne henüz yok; sahne hazır olunca bağlan.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(delta: float) -> void:
	if state != State.PLAY:
		return

	## ── KRONOMETRE ──
	time_left = maxf(0.0, time_left - delta)
	time_changed.emit(time_left)

	## Son 10 saniyede her saniye "tık" sesi (gerginlik).
	var whole: int = int(ceil(time_left))
	if time_left <= 10.0 and whole != _last_tick_second and whole > 0:
		_last_tick_second = whole
		countdown_tick.emit(whole)
		_play_tick()

	## ── MÜZİK HIZLANMASI ──
	_update_music_tempo()

	## ── SÜRE DOLDU ──
	if time_left <= 0.0:
		_end_game(EndReason.TIME_UP)


## ═══════════════════════════════════════════════════════════════════════════
## OYUN AKIŞI
## ═══════════════════════════════════════════════════════════════════════════
func start_game() -> void:
	state = State.PLAY
	time_left = total_time
	score = 0
	_last_tick_second = -1
	_clear_checkpoints()
	state_changed.emit(state)
	time_changed.emit(time_left)
	score_changed.emit(score)


func pause_game() -> void:
	if state == State.PLAY:
		get_tree().paused = true
		state_changed.emit(state)


func resume_game() -> void:
	if state == State.PLAY:
		get_tree().paused = false
		state_changed.emit(state)


## ═══════════════════════════════════════════════════════════════════════════
## CHECKPOINT
## ═══════════════════════════════════════════════════════════════════════════
func register_checkpoint(position: Transform3D) -> int:
	_checkpoints.append({"position": position})
	return _checkpoints.size() - 1


func reach_checkpoint(index: int) -> void:
	_active_checkpoint = index
	checkpoint_reached.emit(index)
	score += 150
	score_changed.emit(score)


## Pasta düştüğünde/ölümcül çarpışmada son checkpoint'e dön.
func respawn_at_checkpoint() -> void:
	if _active_checkpoint < 0:
		## Checkpoint yok → bölüm başlangıcına dön.
		if player:
			player.reset_to(player.global_transform)
			player.balance.reset()
		return
	var cp: Dictionary = _checkpoints[_active_checkpoint]
	if player:
		player.reset_to(cp["position"])
	## Denge sıfırlanır (reset_to içinde), krem yerine oturur.
	## Skor cezası — çocuk dostu: 50 puan.
	score = maxi(0, score - 50)
	score_changed.emit(score)


func _clear_checkpoints() -> void:
	_checkpoints.clear()
	_active_checkpoint = -1


## ═══════════════════════════════════════════════════════════════════════════
## BÖLÜM GEÇİŞİ
## ═══════════════════════════════════════════════════════════════════════════
func advance_level() -> void:
	current_level += 1
	level_changed.emit(current_level)
	if current_level >= LEVEL_SCENES.size():
		_end_game(EndReason.ARRIVED)


## ═══════════════════════════════════════════════════════════════════════════
## OYUN SONU
## ═══════════════════════════════════════════════════════════════════════════
func _end_game(reason: EndReason) -> void:
	if state == State.WIN or state == State.LOSE:
		return
	state = State.WIN if reason == EndReason.ARRIVED else State.LOSE
	end_reason = reason
	state_changed.emit(state)
	game_ended.emit(reason, score)


## ═══════════════════════════════════════════════════════════════════════════
## MÜZİK
## ═══════════════════════════════════════════════════════════════════════════
func _update_music_tempo() -> void:
	if _music == null:
		return
	var ratio: float = clampf(time_left / total_time, 0.0, 1.0)
	## Süre azaldıkça pitch yükselir (tempo artar).
	var target_pitch: float = 1.0 + (1.0 - ratio) * 0.12
	if time_left <= music_rush_threshold:
		target_pitch += 0.06
	_music.pitch_scale = lerpf(_music.pitch_scale, target_pitch, 0.05)


func _play_tick() -> void:
	if _tick:
		_tick.play()


## Sahne ile bağlantı kur.
func bind_scene(player_node: Player, balance_node: CakeBalance,
		music: AudioStreamPlayer = null, tick: AudioStreamPlayer = null) -> void:
	player = player_node
	balance = balance_node
	_music = music
	_tick = tick
	if balance:
		balance.cake_dropped.connect(_on_cake_dropped)
		balance.slip_warning.connect(_on_slip_warning)


func _on_cake_dropped() -> void:
	## Pasta düştü → absürt komik son.
	_end_game(EndReason.CAKE_DROPPED)


func _on_slip_warning() -> void:
	## Krem kaymaya başladı — UI titremeye başlayabilir.
	pass
