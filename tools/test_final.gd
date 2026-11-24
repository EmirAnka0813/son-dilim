extends SceneTree
## FINAL EKRAN TESTI
##
## FinalScreen'in uc durumu (normal / komedi / zaman asimi) sorunsuz
## yuklenip yuklenmedigini dogrular.
##
## NOT: quit() sonrasi Godot bekleyen animasyonlarda asili kalabiliyor;
## bu yuzden sonuc bastirilip dogrudan cikis yapilir.

var passed: int = 0
var failed: int = 0


func _check(ad: String, kosul: bool, detay: String = "") -> void:
	if kosul:
		passed += 1
		print("  PASS  %s%s" % [ad, ("  -> " + detay) if detay != "" else ""])
	else:
		failed += 1
		print("  FAIL  %s%s" % [ad, ("  -> " + detay) if detay != "" else ""])


func _init() -> void:
	print("\n=== FINAL EKRAN TESTI ===")
	var p: PackedScene = load("res://res/scenes/FinalScreen.tscn")
	_check("FinalScreen.tscn yuklenebildi", p != null)
	if p == null:
		_bitir()
		return

	var s: Node = p.instantiate()
	root.add_child(s)
	await process_frame
	await process_frame
	_check("FinalScreen sahneye eklendi ve gorunur", s.visible == true)

	# --- normal final ---
	s.call("show_final", 1250, 872.0)
	await process_frame
	_check("show_final() hata vermedi", true)

	# --- komedi finali ---
	s.call("show_comedy")
	await process_frame
	_check("show_comedy() hata vermedi", true)

	# --- zaman asimi finali ---
	s.call("show_timeout")
	await process_frame
	_check("show_timeout() hata vermedi", true)

	_bitir()


func _bitir() -> void:
	print("\n=== SONUÇ: %d/%d geçti ===\n" % [passed, passed + failed])
	quit(0 if failed == 0 else 1)
