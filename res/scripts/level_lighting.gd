class_name LevelLighting
extends RefCounted
##
## ORTAK IŞIK & ATMOSFER KURULUMU
## ============================================================================
## Tüm bölümler bu statik yardımcıyı kullanır — böylece "ışık stratejisi"
## sahneden sahneye kopyalanmaz, tek yerden yönetilir.
##
## ── environment-world-builder: "Her ışığın amacı olmalı" ─────────────────────
## ── graphics-realism-expert: "Sıcak/soğuk bölünme sinematik hissin en ucuz yolu"
##
##   · Ana yönlü ışık → genel yön + gölge yönü
##   · Soğuk ambient   → gölgeler mavi
##   · Sıcak yapay ışık→ sıcak vurgular (her bölüm kendi ekler)
##   · Sis            → derinlik ayrımı
##   · Glow            → neon parlaması
##
## BÖLÜM SEÇENEKLERİ:
##   interior : ofis — soğuk mavi floresan, düşük ambient, kapalı
##   street   : sokak — yağmurlu akşam, sıcak lambalar + soğuk ambient
##   metro    : istasyon — soğuk mavi floresan, sisli
##   hill     : yokuş — akşam, sıcak ev ışıkları + soğuk gökyüzü
## ============================================================================

## Bölüm tipine göre ortam kur.
static func setup(host: Node3D, kind: String) -> void:
	if host == null:
		return
	var env := Environment.new()

	match kind:
		"interior":
			_setup_interior(host, env)
		"metro":
			_setup_metro(host, env)
		"hill":
			_setup_hill(host, env)
		_:
			_setup_street(host, env)

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	host.add_child(world_env)


## ── OFİS: soğuk mavi floresan, kapalı, alçak ambient ────────────────────────
static func _setup_interior(host: Node3D, env: Environment) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.030, 0.035, 0.055)
	## Soğuk mavi ambient (floresan).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.48, 0.64)
	env.ambient_light_energy = 1.60
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.tonemap_white = 5.0
	## İç mekânda sis az.
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.15, 0.24)
	env.fog_light_energy = 0.5
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	## Tavan floresanları (soğuk beyaz).
	var light := DirectionalLight3D.new()
	light.light_color = Color(0.86, 0.90, 1.0)
	light.light_energy = 1.6
	light.shadow_enabled = true
	light.shadow_bias = 0.05
	light.shadow_normal_bias = 1.5
	light.directional_shadow_max_distance = 60.0
	light.rotation_degrees = Vector3(-72, 35, 0)
	host.add_child(light)


## ── SOKAK: yağmurlu akşam, sıcak lambalar + soğuk gökyüzü ──────────────────
static func _setup_street(host: Node3D, env: Environment) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.055, 0.095)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.30, 0.46)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.13, 0.22)
	env.fog_light_energy = 0.9
	env.fog_density = 0.014
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	## AY: soğuk mavi, yumuşak gölge.
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	moon.shadow_bias = 0.04
	moon.shadow_normal_bias = 1.4
	moon.directional_shadow_max_distance = 70.0
	moon.rotation_degrees = Vector3(-38, 145, 0)
	host.add_child(moon)

	## DOLGU: gölge tarafı soğuk kalır.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.40, 0.50, 0.78)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-15, -40, 0)
	host.add_child(fill)

	## REFLECTION PROBE: ıslak yol neonları yansıtsın.
	var probe := ReflectionProbe.new()
	probe.size = Vector3(90, 14, 40)
	probe.position = Vector3(35, 6, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	host.add_child(probe)


## ── METRO: soğuk floresan istasyon, sisli ─────────────────────────────────
static func _setup_metro(host: Node3D, env: Environment) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.020, 0.025, 0.040)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.58)
	env.ambient_light_energy = 1.30
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 5.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.14, 0.22)
	env.fog_light_energy = 0.8
	env.fog_density = 0.010
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.2
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	## Tavan floresanları (soğuk, sert).
	var light := DirectionalLight3D.new()
	light.light_color = Color(0.80, 0.88, 1.0)
	light.light_energy = 1.35
	light.shadow_enabled = true
	light.shadow_bias = 0.05
	light.shadow_normal_bias = 1.4
	light.directional_shadow_max_distance = 55.0
	light.rotation_degrees = Vector3(-80, 20, 0)
	host.add_child(light)


## ── YOKUŞ: akşam, sıcak ev ışıkları + soğuk gökyüzü ───────────────────────
static func _setup_hill(host: Node3D, env: Environment) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.065, 0.115)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.40, 0.60)
	env.ambient_light_energy = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.08
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.15, 0.26)
	env.fog_light_energy = 1.0
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	## ALACAKANLIK: soğuk mavi, alçak açı → uzun gölgeler.
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.70
	moon.shadow_enabled = true
	moon.shadow_bias = 0.04
	moon.shadow_normal_bias = 1.4
	moon.directional_shadow_max_distance = 80.0
	moon.rotation_degrees = Vector3(-26, 160, 0)
	host.add_child(moon)

	## SICAK DOLGU: ev yönünden gelen tüm ton.
	var warm := DirectionalLight3D.new()
	warm.light_color = Color(1.0, 0.82, 0.60)
	warm.light_energy = 0.30
	warm.shadow_enabled = false
	warm.rotation_degrees = Vector3(-32, -50, 0)
	host.add_child(warm)
