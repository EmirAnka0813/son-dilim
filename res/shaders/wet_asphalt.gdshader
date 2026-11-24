shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// ═══════════════════════════════════════════════════════════════════════════
// SON DİLİM — ISLAK ASFALT (WET ASPHALT)
// ═══════════════════════════════════════════════════════════════════════════
// Fiziksel gerekçe:
//   "Su, asfaltın mikro gözeneklerini doldurur; bu yüzden ıslak yüzeyin
//    pürüzlülüğü çöker (0.85 → 0.08) ve normal detayı düzleşir (su boşlukları
//    doldurur). Böylece gökyüzü ve neon tabelalar yansıma ile görünür."
//
// Sonuç: KURU bölgeler mat ve detaylı, ISLAK bölgeler ayna gibi ve pürüzsüz.
//
// Kullanım:
//   ShaderMaterial al → albedo_texture = asphalt_albedo.png
//                       normal_texture = asphalt_normal.png
//                       wetness = 0.0 (kurak) … 1.0 (tam ıslak)
// ═══════════════════════════════════════════════════════════════════════════

group_uniforms Base;
// ── Albedo ──────────────────────────────────────────────────────────────────
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float uv_scale_x : hint_range(0.1, 50.0) = 8.0;
uniform float uv_scale_y : hint_range(0.1, 50.0) = 3.0;

group_uniforms Surface;
// ── Normal detayı (sadece kurak bölgelerde) ────────────────────────────────
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;

group_uniforms Wetness;
// ── Islaklık kontrolü ──────────────────────────────────────────────────────
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
// Su birikintisi eşiği: bundan DARK olan albedo = su birikmiştir.
// DÜŞÜK eşik = daha çok alan ıslak.
uniform float puddle_threshold : hint_range(0.0, 1.0) = 0.42;
uniform float dry_roughness : hint_range(0.0, 1.0) = 0.88;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.06;
// Su tabakasının kalınlığı → specular gücü (yapay clearcoat)
uniform float wet_specular : hint_range(0.0, 1.0) = 0.92;

group_uniforms Rain;
// ── Yağmur animasyonu (canlı dalgalar) ─────────────────────────────────────
uniform float rain_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rain_speed : hint_range(0.0, 5.0) = 1.4;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.25;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// ── UV ───────────────────────────────────────────────────────────────────
	vec2 uv = UV * vec2(uv_scale_x, uv_scale_y);

	// ── Albedo ───────────────────────────────────────────────────────────────
	vec4 albedo_sample = texture(albedo_tex, uv);
	vec3 albedo = albedo_sample.rgb * base_tint.rgb;

	// ── Su birikintisi maskesi ───────────────────────────────────────────────
	// Fizik: Su, alçak (koyu) noktalarda birikir. Albedo'nun parlaklığı
	// düşükse orası çukur → su.
	// smoothstep(edge0 > edge1) → DÜŞÜŞ eğrisi üretir (ters eşik).
	float luminance = dot(albedo_sample.rgb, vec3(0.2126, 0.7152, 0.0722));
	float pool = smoothstep(puddle_threshold, puddle_threshold - 0.18, luminance);

	// Islaklık maskesi (genel yağmur ıslaklığı × birikinti alanı)
	float wet_mask = pool * wetness;

	// ── Normal ───────────────────────────────────────────────────────────────
	vec3 dry_normal = texture(normal_tex, uv).rgb;
	vec3 flat_normal = vec3(0.5, 0.5, 1.0);

	// Yağmur dalgaları: ıslak yüzeyde kayan halkalar.
	// İki farklı frekans + kaydırma = kaotik ama okunabilir ripple.
	if (rain_amount > 0.001) {
		vec2 ruv = world_pos.xz * 0.55;
		float w1 = sin((ruv.x * 3.1 + ruv.y * 2.3) + TIME * rain_speed * 2.0);
		float w2 = sin((ruv.x * -1.7 + ruv.y * 4.1) + TIME * rain_speed * 3.1);
		float ripple = (w1 * 0.6 + w2 * 0.4) * rain_amount * ripple_strength;
		// Ripple sadece ıslak bölgelerde (su üstünde).
		ripple *= wet_mask;
		// Normal'ı XY düzleminde kaydır (dik yönü koru).
		dry_normal.xy += vec2(ripple, ripple * 0.7) * 0.5;
	}

	// Su mikro boşlukları doldurur → normal detayı DÜZLEŞİR.
	vec3 normal_final = mix(dry_normal, flat_normal, wet_mask);
	NORMAL_MAP = normal_final;
	NORMAL_MAP_DEPTH = 1.0;

	// ── Roughness ────────────────────────────────────────────────────────────
	// Kuru asfalt: pürüzlü (0.88) → ışığı dağıtır, mat görünür.
	// Islak asfalt: pürüzsüz (0.06) → yansıma keskin, ayna gibi.
	float roughness = mix(dry_roughness, wet_roughness, wet_mask);

	// Yağmur her yere yağıyorsa genel bir ıslaklık katmanı.
	roughness = mix(roughness, wet_roughness * 1.6, rain_amount * 0.35);

	ROUGHNESS = clamp(roughness, 0.02, 1.0);
	METALLIC = 0.0;

	// ── Albedo değişimi ──────────────────────────────────────────────────────
	// Islak asfalt daha KOYU görünür (su ışığı içeri alır, yüzey koyulaşır).
	albedo *= mix(1.0, 0.55, wet_mask);
	// Yağmur ıslaklığı da koyulatır.
	albedo *= mix(1.0, 0.72, rain_amount * 0.5);
	ALBEDO = albedo;

	// ── Specular (yapay clearcoat) ───────────────────────────────────────────
	// Su tabakası ince bir şeffaf katman → yansımayı güçlendirir.
	SPECULAR = mix(0.5, wet_specular, wet_mask);

	// ── Ambient Occlusion ────────────────────────────────────────────────────
	// Islak bölgelerde su birikintileri çukur → AO düşer.
	// ── Ambient Occlusion ────────────────────────────────────────────────────
	// Islak bölgelerde su birikintileri çukur → AO düşer.
	// NOT: Godot 4 spatial shader'da değişken adı "AO" (OCCLUSION değil).
	AO = mix(1.0, 0.72, pool * wetness);

	// ── Fresnel tabanlı kenar yansıması ─────────────────────────────────────
	// Grazing açılarda yansıma güçlenir (Schlick, üstel 5).
	// Bu, ıslak yolun uzaktan parlamasını sağlar.
	vec3 view_dir = normalize(VIEW);
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), view_dir), 0.0, 1.0), 5.0);
	EMISSION += vec3(0.03, 0.05, 0.09) * fresnel * wet_mask * 0.5;
}
