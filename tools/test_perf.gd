extends SceneTree
##
## PERFORMANS TESTİ — çizim çağrısı (draw call) ve FPS ölçümü
## ============================================================================
## Çalıştırma:
##   godot --headless --script res://tools/test_perf.gd
##
## Ölçülenler:
##   · Çizim çağrısı (draw calls) — sahne karmaşıklığının ana göstergesi
##   · Nesne sayısı
##   · Üçgen sayısı
##   · Bellek (ObjectDB)
##
## NOT: Headless modda gerçek FPS ölçülemez (render yok). Bu yüzden
## sahne karmaşıklığı ölçülür; FPS için gerçek pencere gerekir
## (tools/shot.gd --auto-shot ile render alınır).
## ============================================================================

var passed: int = 0
var failed: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("  PASS  ", label, (" -> " + detail) if detail != "" else "")
	else:
		failed += 1
		print("  FAIL  ", label, (" -> " + detail) if detail != "" else "")


func _init() -> void:
	print("\n=== SON DİLİM — PERFORMANS ÖLÇÜMÜ ===\n")
	_run.call_deferred()


func _run() -> void:
	await process_frame

	var packed: PackedScene = load("res://res/scenes/Main.tscn")
	if packed == null:
		_check("Main.tscn yükleniyor", false)
		_finish()
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var level_root: Node3D = main.get_node_or_null("LevelRoot")
	var game: GameManager = main.get_node_or_null("GameManager")

	## ── BÖLÜM 1: OFİS ──
	_measure("Bölüm 1 (Ofis)", level_root, 1)

	## ── BÖLÜM 2: SOKAK ──
	main.call("advance_to_next_level")
	await create_timer(1.6).timeout
	await process_frame
	_measure("Bölüm 2 (Sokak)", level_root, 2)

	## ── BÖLÜM 3: METRO ──
	main.call("advance_to_next_level")
	await create_timer(1.6).timeout
	await process_frame
	_measure("Bölüm 3 (Metro)", level_root, 3)

	## ── BÖLÜM 4: YOKUŞ ──
	main.call("advance_to_next_level")
	await create_timer(1.6).timeout
	await process_frame
	_measure("Bölüm 4 (Yokuş)", level_root, 4)

	## ── GENEL KONTROL ──
	var objects: int = Performance.get_monitor(Performance.OBJECT_COUNT)
	var nodes: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	print("\n  Genel: %d nesne, %d node" % [objects, nodes])
	_check("Nesne sayısı makul (<5000)", objects < 5000, "%d" % objects)

	_finish()


## Bir bölümün karmaşıklığını ölç.
func _measure(label: String, level_root: Node3D, expected_level: int) -> void:
	var level: Node = null
	for child in level_root.get_children():
		if child.has_method("get_level_index") \
				and int(child.get_level_index()) == expected_level - 1:
			level = child
			break
	if level == null:
		_check("%s bulundu" % label, false)
		return

	## Sahne ağacını say.
	var stats: Array = [0, 0, 0]   # [mesh, ışık, üçgen]
	_count_nodes(level, stats)
	var mesh_count: int = stats[0]
	var light_count: int = stats[1]
	var tri_count: int = stats[2]

	## Render sunucusundan çizim çağrısı.
	var draw_calls: int = int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))

	print("  %s:" % label)
	print("    mesh      : %d" % mesh_count)
	print("    ışık      : %d" % light_count)
	print("    üçgen     : ~%d" % tri_count)
	print("    draw call : %d" % draw_calls)
	print("    nesne     : %d" % objects)

	_check("%s — draw call makul (<600)" % label, draw_calls < 600,
		"%d" % draw_calls)
	_check("%s — üçgen sayısı makul (<500k)" % label, tri_count < 500000,
		"~%d" % tri_count)
	_check("%s — ışık sayısı makul (<40)" % label, light_count < 40,
		"%d" % light_count)


## Mesh / ışık / üçgen say.
## NOT: GDScript'te int parametreleri değer olarak kopyalanır (pass-by-value),
## bu yüzden recursive sayaçlar KAYBOLUR. Sayılar bir Array içinde tutulur.
func _count_nodes(node: Node, stats: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			stats[0] += 1
			var mesh: Mesh = (child as MeshInstance3D).mesh
			if mesh != null:
				stats[2] += _mesh_triangles(mesh)
		elif child is Light3D:
			stats[1] += 1
		_count_nodes(child, stats)


## Mesh üçgen sayısı (yüzey = triangle).
func _mesh_triangles(mesh: Mesh) -> int:
	if mesh is ArrayMesh:
		var total: int = 0
		for i in (mesh as ArrayMesh).get_surface_count():
			var arrays: Array = (mesh as ArrayMesh).surface_get_arrays(i)
			if arrays.size() > 0 and arrays[Mesh.ARRAY_VERTEX] != null:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.size() > 0:
					total += indices.size() / 3
				else:
					total += verts.size() / 3
		return total
	elif mesh is PrimitiveMesh:
		return 12   # kutu ≈ 12 üçgen
	return 0


func _finish() -> void:
	print("\n=== SONUÇ: %d/%d geçti ===\n" % [passed, passed + failed])
	quit(0 if failed == 0 else 1)
