#!/usr/bin/env blender
"""
SON DİLİM — Blender Asset Üretim Betiği
===============================================================================
Çalıştırma:
    blender --background --python tools/build_assets.py

Üretilen modeller (GLB, Godot'a hazır):
    res/assets/models/character.glb      Buyuk abi — stilize low-poly
    res/assets/models/cake_box.glb       Pasta kutusu (krem + mum + çilek)
    res/assets/models/cake_box_open.glb  Açık kutu (pasta görünür)
    res/assets/models/buildings.glb     apartman cephanesi (modüler)
    res/assets/models/taxi.glb           Taksi
    res/assets/models/minibus.glb        Minibüs (dolmuş)
    res/assets/models/street_lamp.glb    Sokak lambası
    res/assets/models/bicycle.glb        Bisiklet
    res/assets/models/hydrant.glb        Yangın hydrantı
    res/assets/models/dog.glb            Sokak köpeği
    res/assets/models/crate.glb          Sebze kasası

TASARIM İLKESİ (stilyze low-poly):
    · Düşük poligon sayısı (oyun performansı) ama SILUET okunur
    · Düz gölgelendirme (flat shading) + keskin renk blokları
    · Gerçekçi değil, STİLİZE — Pixar/Arcade hissi
    · Her mesh tek renk malzeme, UV yok (doku yerine vertex renk)
===============================================================================
"""

import bpy
import math
import os
import sys

# ── YOLLAR ─────────────────────────────────────────────────────────────────
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(PROJECT, "res", "assets", "models")
os.makedirs(OUT_DIR, exist_ok=True)

# ── RENK PALETİ ────────────────────────────────────────────────────────────
PALETTE = {
    "skin":       (0.92, 0.74, 0.62, 1.0),
    "skin_dark":  (0.78, 0.58, 0.46, 1.0),
    "hair":       (0.24, 0.13, 0.07, 1.0),
    "shirt":      (0.22, 0.42, 0.68, 1.0),   # mavi gömlek
    "jacket":     (0.30, 0.32, 0.38, 1.0),   # ceket
    "pants":      (0.20, 0.20, 0.26, 1.0),
    "shoe":       (0.14, 0.12, 0.13, 1.0),
    "box":        (0.72, 0.52, 0.30, 1.0),   # kahverengi kutu
    "box_lid":    (0.82, 0.64, 0.40, 1.0),
    "cream":      (1.00, 0.97, 0.94, 1.0),
    "cake":       (0.92, 0.76, 0.52, 1.0),
    "candle":     (0.95, 0.92, 0.80, 1.0),
    "flame":      (1.00, 0.75, 0.25, 1.0),
    "berry":      (0.86, 0.16, 0.24, 1.0),
    "taxi":       (0.98, 0.72, 0.10, 1.0),
    "bus":        (0.30, 0.55, 0.42, 1.0),
    "car_blue":   (0.18, 0.30, 0.55, 1.0),
    "glass":      (0.18, 0.26, 0.34, 1.0),
    "tire":       (0.07, 0.07, 0.08, 1.0),
    "chrome":     (0.72, 0.74, 0.78, 1.0),
    "headlight":  (1.00, 0.94, 0.70, 1.0),
    "taillight":  (0.85, 0.12, 0.10, 1.0),
    "building":   (0.42, 0.38, 0.50, 1.0),
    "building2":  (0.52, 0.42, 0.44, 1.0),
    "window_lit": (1.00, 0.84, 0.52, 1.0),
    "window_dark": (0.16, 0.18, 0.26, 1.0),
    "neon_pink":  (1.00, 0.32, 0.68, 1.0),
    "neon_cyan":  (0.28, 0.82, 1.00, 1.0),
    "metal":      (0.42, 0.44, 0.48, 1.0),
    "lamp_glow":  (1.00, 0.88, 0.62, 1.0),
    "dog":        (0.36, 0.26, 0.18, 1.0),
    "crate":      (0.66, 0.48, 0.28, 1.0),
    "veg_green":  (0.32, 0.58, 0.28, 1.0),
    "veg_red":    (0.78, 0.22, 0.18, 1.0),
    "orange":     (0.92, 0.42, 0.12, 1.0),
    "hydrant":    (0.82, 0.18, 0.14, 1.0),
}

# ── YARDIMCI FONKSİYONLAR ──────────────────────────────────────────────────
## Koordinat dönüşümü: model Y-up (x=sağ, y=yükseklik, z=derinlik)
## Blender Z-up (x=sağ, y=derinlik, z=yükseklik).
##
##   (x, y, z)_Y-up → (x, z, -y)_Z-up
##
## Yön: modelin önü +Z'de → Blender'da -Y'de (ileri yön korunur).
def _to_blender(loc):
    # (x, y, z)_model -> (x, z, y)_Blender
    # Model bu scriptte Y-up mantığında kurulur: y = yükseklik, z = derinlik.
    # Blender Z-up'tur: z = yükseklik, y = derinlik.
    # Dönüşüm determinant +1 (ayna değil): Y↔Z takas + işaret düzeltmesi.
    return (loc[0], loc[2], loc[1])


## Euler dönüşümü (derece): Y-up → Z-up.
## Y-up'taki pitch (X ekseni) ve yaw (Y ekseni) korunur; sadece
## referans ekseni değişir, bu yüzden +90° X offset uygulanır.
def _to_blender_rot(rot):
    # Y-up (pitch=X, yaw=Z) -> Z-up (pitch=Y, yaw=Z)
    # dönüşüm: (rx, ry, rz) -> (ry, rx, rz) — Y↔Z takası.
    return (math.radians(rot[1]),
            math.radians(rot[0]),
            math.radians(rot[2]))



def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        bpy.data.materials.remove(block)


def mat(name):
    """Paletten malzeme al (yoksa oluştur)."""
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    color = PALETTE.get(name, (0.8, 0.8, 0.8, 1.0))
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.72
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.28
    return m


def box(name, size, loc, rot=(0, 0, 0), material=None, parent=None):
    """Boyutlu kutu primitive'i ekle.

    KOORDİNAT DÖNÜŞÜMÜ: Model Y-up mantığında kurulur
    (x = sağ, y = yükseklik, z = derinlik). Blender Z-up'tur.
    Bu yüzden konum (x, y, z) → (x, z, -y) olarak çevrilir ve
    nesne X ekseninde -90° döndürülür.
    """
    bpy.ops.mesh.primitive_cube_add(
        size=1, location=_to_blender(loc), rotation=_to_blender_rot(rot))
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if material:
        obj.data.materials.append(mat(material))
    if parent:
        obj.parent = parent
    return obj


def cyl(name, radius, depth, loc, rot=(0, 0, 0), material=None, verts=12,
        parent=None):
    """Silindir primitive'i ekle."""
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth,
        location=_to_blender(loc), rotation=_to_blender_rot(rot))
    obj = bpy.context.object
    obj.name = name
    if material:
        obj.data.materials.append(mat(material))
    if parent:
        obj.parent = parent
    return obj


def sphere(name, radius, loc, material=None, scale=(1, 1, 1), parent=None,
           segs=12, rings=8):
    """Küre primitive'i ekle."""
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segs, ring_count=rings, radius=radius,
        location=_to_blender(loc))
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if material:
        obj.data.materials.append(mat(material))
    if parent:
        obj.parent = parent
    return obj


def cone(name, radius, depth, loc, rot=(0, 0, 0), material=None, verts=10,
         parent=None):
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts, radius1=radius, radius2=0.0, depth=depth,
        location=_to_blender(loc), rotation=_to_blender_rot(rot))
    obj = bpy.context.object
    obj.name = name
    if material:
        obj.data.materials.append(mat(material))
    if parent:
        obj.parent = parent
    return obj


def torus(name, major, minor, loc, rot=(0, 0, 0), material=None, parent=None):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=14, minor_segments=6,
        location=_to_blender(loc), rotation=_to_blender_rot(rot),
        major_radius=major, minor_radius=minor)
    obj = bpy.context.object
    obj.name = name
    if material:
        obj.data.materials.append(mat(material))
    if parent:
        obj.parent = parent
    return obj


def shade_flat(obj):
    """Stilize görünüm: düz gölgelendirme."""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_flat()


def join_objects(objects, name):
    """Mesh'leri birleştir (Godot için tek mesh daha verimli)."""
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    return result


def export_glb(objects, filename, origin=(0, 0, 0)):
    """Seçili objeleri GLB olarak kaydet."""
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]

    # Toplama noktasını sıfırlama (model merkezli olsun).
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.context.scene.cursor.location = origin

    # EKSEN DÖNÜŞÜMÜ — KRİTİK:
    #
    # glTF standardı Y-up'tir; Blender Z-up'tir. export_yup=True bu
    # dönüşümü YAPAR. Ama biz modeli Blender'da Y-up koordinatlarla
    # kuruyoruz (y = boy, z = derinlik) — yani model zaten Y-up mantığında.
    # export_yup=True ile ÇİFT dönüşüm oluyor ve KARAKTER YATIK İMPORTE
    # EDİLİYOR (ölçülen: y=0.66m, z=2.20m — karakter yatık!).
    #
    # Çözüm: export_yup=False. Model Godot'a kurulduğu gibi gelir:
    # Y = yukarı, Z = derinlik (ön = -Z), X = sağ.
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials='EXPORT',
        export_normals=True,
    )
    size_kb = os.path.getsize(path) // 1024
    print(f"  ✓ {filename}  ({size_kb} KB)")


# ═══════════════════════════════════════════════════════════════════════════
# KARAKTER — BÜYÜK ABI
# ═══════════════════════════════════════════════════════════════════════════
def build_character():
    """Büyük abi: 13-14 yaşında, Derin'in 10 yaşına giren kardeşi.
    Stilize low-poly, orantılı çocuk figürü (uzun kol/bacak oranı)."""
    clear_scene()
    parts = []

    # Gövde — 13-14 yaş abi oranı: omuzlar geniş (0.56), gövde uzun,
    # bacaklar gövdeden uzun, kafa gövdeye göre KÜÇÜK (çocuk değil).
    parts.append(box("Torso", (0.56, 0.70, 0.32), (0, 1.28, 0),
                     material="jacket"))
    # Göğüs cebi + ceket detayı
    parts.append(box("JacketStripe", (0.58, 0.05, 0.34), (0, 0.97, 0),
                     material="shirt"))
    # Kemer
    parts.append(box("Belt", (0.58, 0.09, 0.34), (0, 0.93, 0), material="pants"))

    # Kalça
    parts.append(box("Hips", (0.50, 0.24, 0.30), (0, 0.82, 0), material="pants"))

    # Bacaklar — uzun (büyük abi oranı)
    for s in (-1, 1):
        parts.append(box(f"Thigh_{s}", (0.20, 0.50, 0.22),
                         (s * 0.15, 0.53, 0), material="pants"))
        parts.append(box(f"Shin_{s}", (0.18, 0.46, 0.20),
                         (s * 0.15, 0.12, 0), material="pants"))
        # Ayakkabı (bastonlu topuklu stil, basit)
        parts.append(box(f"Shoe_{s}", (0.21, 0.12, 0.32),
                         (s * 0.15, 0.06, 0.06), material="shoe"))
        parts.append(box(f"Heel_{s}", (0.19, 0.08, 0.10),
                         (s * 0.15, 0.09, -0.09), material="shoe"))

    # Kollar — pasta kutusu ELDE taşınacak: kollar öne doğru kıvrık,
    # eller göğüs hizasında ve birbirine yakın (kutu genişliği ~0.56).
    #
    # Anatomik olarak: omuz → dirsek aşağı-öne → bilek öne-yukarı.
    # Bu, ağır bir kutuyu göğse yakın tutan doğal duruş.
    for s in (-1, 1):
        # Üst kol: omuzdan aşağıya, hafif öne
        parts.append(box(f"UpperArm_{s}", (0.15, 0.36, 0.16),
                         (s * 0.35, 1.42, 0.03), material="jacket"))
        # Alt kol: öne ve yukarı (dirsekten ele).
        parts.append(box(f"ForeArm_{s}", (0.13, 0.22, 0.32),
                         (s * 0.30, 1.20, 0.20),
                         rot=(math.radians(-38), 0, math.radians(s * 8)),
                         material="jacket"))
        # El: kutunun yan kenarında — kutu genişliği 0.62 → eller ±0.31.
        # Z = +0.36 (karakterin önünde, kutunun arkasında).
        parts.append(sphere(f"Hand_{s}", 0.095, (s * 0.31, 1.26, 0.36),
                            material="skin", scale=(1, 1.1, 0.85)))

    # Boyun + kafa — kafa gövdeye göre küçük (ergin oran)
    parts.append(cyl("Neck", 0.078, 0.12, (0, 1.68, 0), material="skin"))
    parts.append(sphere("Head", 0.225, (0, 1.90, 0), material="skin",
                        scale=(0.94, 1.06, 0.94), segs=14, rings=10))
    # Çene (daha belirgin — ergin yüz hatları)
    parts.append(sphere("Chin", 0.155, (0, 1.80, 0.04), material="skin",
                        scale=(0.90, 0.78, 0.96)))

    # Saç (kısa erkek saçı — bloklar)
    parts.append(sphere("HairCap", 0.238, (0, 1.945, -0.01), material="hair",
                        scale=(0.98, 0.92, 1.0), segs=14, rings=8))
    parts.append(box("HairFront", (0.32, 0.10, 0.10), (0, 2.02, 0.17),
                     material="hair"))
    parts.append(box("HairSideL", (0.07, 0.19, 0.16), (-0.19, 1.91, 0.02),
                     material="hair"))
    parts.append(box("HairSideR", (0.07, 0.19, 0.16), (0.19, 1.91, 0.02),
                     material="hair"))
    parts.append(box("HairBack", (0.27, 0.21, 0.10), (0, 1.91, -0.17),
                     material="hair"))

    # Yüz
    for s in (-1, 1):
        parts.append(sphere(f"Eye_{s}", 0.044, (s * 0.085, 1.94, 0.205),
                            material="window_dark", scale=(1, 1.05, 0.6),
                            segs=10, rings=6))
        parts.append(box(f"Brow_{s}", (0.105, 0.026, 0.026),
                         (s * 0.085, 2.005, 0.215), material="hair"))
    parts.append(sphere("Nose", 0.043, (0, 1.895, 0.225), material="skin",
                        scale=(0.85, 1.05, 1.25), segs=8, rings=6))
    parts.append(box("Mouth", (0.095, 0.022, 0.02), (0, 1.80, 0.205),
                     material="skin_dark"))

    # SIRT ÇANTASI YOK — pasta kutusu ELDE taşınıyor (hikâye: "elinde
    # devasa pasta kutusu"). Sırt boş, askı yok.

    for p in parts:
        shade_flat(p)
    export_glb(parts, "character.glb")


# ═══════════════════════════════════════════════════════════════════════════
# PASTA KUTUSU
# ═══════════════════════════════════════════════════════════════════════════
def build_cake_box(open_lid=False):
    """Pasta kutusu: kahverengi kutu + krem + mumlar + çilek.

    ÖLÇÜ: kutu göğse sığmalı ama "devasa" hissi vermeli.
    Eller arası genişlik ~0.54 → kutu 0.62 geniş (eller yanlardan taşar).
    """
    clear_scene()
    parts = []
    W, H, D = 0.62, 0.46, 0.50

    # Kutu gövdesi
    #
    # Z İŞARETİ: Karakter mesh'i Godot'ta 180° döndürülüyor. Bu yüzden
    # Blender'daki +Z, Godot'ta -Z'ye dönüşür. Kutunun "önü" (kapağın
    # açıldığı yön, mumların göründüğü yön) karakterin önünde olmalı.
    # Bu yüzden burada Z = 0 merkez, mumlar +Y'de (yukarıda).
    parts.append(box("BoxBody", (W, H, D), (0, 0, 0), material="box"))
    # Kutu içi (krem görünümü için hafif içeride)
    parts.append(box("BoxInner", (W - 0.06, H - 0.06, D - 0.06),
                     (0, 0.02, 0), material="cream"))

    if open_lid:
        # Açık kapak (arkaya yatık) — kapak -Z tarafına açılır
        parts.append(box("BoxLid", (W + 0.04, 0.05, D + 0.04),
                         (0, H * 0.62, -D * 0.62),
                         rot=(math.radians(-58), 0, 0), material="box_lid"))
    else:
        # Kapalı kapak
        parts.append(box("BoxLid", (W + 0.04, 0.05, D + 0.04),
                         (0, H * 0.5 + 0.02, 0), material="box_lid"))
        # Kutu bandı (kırmızı bant)
        parts.append(box("BoxBand", (W + 0.05, 0.07, 0.07),
                         (0, H * 0.5 + 0.02, 0), material="berry"))

    # Pasta (kutu içinden taşan)
    parts.append(cyl("Cake", 0.185, 0.34, (0, 0.28, 0), material="cake",
                     verts=14))
    # Krem katmanı
    parts.append(cyl("CreamTop", 0.19, 0.05, (0, 0.46, 0), material="cream",
                     verts=14))
    # Krem dalgası
    parts.append(torus("CreamWave", 0.187, 0.019, (0, 0.445, 0),
                       rot=(math.radians(90), 0, 0), material="cream"))
    # Çilekler
    for i in range(5):
        a = (i / 5.0) * math.tau
        parts.append(sphere(f"Berry{i}", 0.030,
                            (math.cos(a) * 0.11, 0.495, math.sin(a) * 0.11),
                            material="berry", segs=8, rings=6))
    # Mumlar (10 adet — Derin 10 yaşına giriyor!)
    for i in range(10):
        x = -0.105 + i * 0.0233
        parts.append(cyl(f"Candle{i}", 0.010, 0.15, (x, 0.555, 0),
                         material="candle", verts=6))
        parts.append(cone(f"Flame{i}", 0.012, 0.038, (x, 0.648, 0),
                          material="flame", verts=6))

    for p in parts:
        shade_flat(p)
    export_glb(parts, "cake_box_open.glb" if open_lid else "cake_box.glb")


# ═══════════════════════════════════════════════════════════════════════════
# BİNALAR (modüler cephe)
# ═══════════════════════════════════════════════════════════════════════════
def build_buildings():
    """Apartman cephanesi: gövde + pencereler + balkon + klima + tabela."""
    clear_scene()
    parts = []
    W, H, D = 10.0, 16.0, 8.0

    parts.append(box("BuildingBody", (W, H, D), (0, H * 0.5, 0),
                     material="building"))
    # Kat silmeleri
    for f in range(1, 5):
        parts.append(box(f"FloorLine{f}", (W + 0.16, 0.22, D + 0.16),
                         (0, f * (H / 5.0), 0), material="building2"))
    # Pencereler (ön + arka)
    for row in range(5):
        for col in range(3):
            x = -W / 2 + W / 4 + col * (W / 2 - 1.0)
            y = 1.6 + row * (H / 5.2)
            lit = (row + col) % 3 != 0
            parts.append(box(f"WinF{row}{col}", (1.5, 1.7, 0.16),
                             (x, y, D / 2 + 0.02),
                             material="window_lit" if lit else "window_dark"))
            parts.append(box(f"WinB{row}{col}", (1.5, 1.7, 0.16),
                             (x, y, -D / 2 - 0.02),
                             material="window_dark"))
            # pervaz
            parts.append(box(f"Sill{row}{col}", (1.8, 0.12, 0.28),
                             (x, y - 0.92, D / 2 + 0.08),
                             material="building2"))
    # Balkonlar
    for row in range(1, 5, 2):
        y = 1.6 + row * (H / 5.2) - 1.5
        parts.append(box(f"Balcony{row}", (4.2, 0.18, 1.3),
                         (0, y, D / 2 + 0.6), material="building2"))
        parts.append(box(f"Railing{row}", (4.2, 0.9, 0.08),
                         (0, y + 0.5, D / 2 + 1.2), material="metal"))
    # Klima üniteleri
    for row in range(4):
        y = 2.6 + row * (H / 5.2)
        parts.append(box(f"AC{row}", (0.9, 0.7, 0.6),
                         (W / 2 - 1.5, y, D / 2 + 0.3), material="chrome"))
    # Neon tabela
    parts.append(box("NeonBack", (4.6, 1.3, 0.3), (0, 3.4, D / 2 + 0.2),
                     material="building2"))
    for i in range(5):
        parts.append(box(f"NeonBar{i}", (0.42, 0.7, 0.14),
                         (-1.5 + i * 0.75, 3.4, D / 2 + 0.38),
                         material="neon_pink" if i % 2 == 0 else "neon_cyan"))
    # Dükkan (zemin kat)
    parts.append(box("ShopFront", (6.5, 2.6, 0.2), (0, 1.3, D / 2 + 0.05),
                     material="glass"))
    parts.append(box("Awning", (7.2, 0.16, 1.6), (0, 2.9, D / 2 + 0.7),
                     rot=(math.radians(-16), 0, 0), material="neon_pink"))
    # Çatı
    parts.append(box("RoofEdge", (W + 0.5, 0.4, D + 0.5), (0, H + 0.2, 0),
                     material="building2"))

    for p in parts:
        shade_flat(p)
    export_glb(parts, "buildings.glb")


# ═══════════════════════════════════════════════════════════════════════════
# ARAÇLAR
# ═══════════════════════════════════════════════════════════════════════════
def build_vehicle(name, kind):
    """Taksi / minibüs / sedan."""
    clear_scene()
    parts = []
    if kind == "minibus":
        L, H, W = 6.0, 3.0, 2.4
        body_mat = "bus"
    elif kind == "taxi":
        L, H, W = 4.4, 1.6, 2.0
        body_mat = "taxi"
    else:
        L, H, W = 4.6, 1.5, 2.0
        body_mat = "car_blue"

    # Gövde
    parts.append(box("Body", (L, H, W), (0, H * 0.5 + 0.45, 0),
                     material=body_mat))
    # Kabin / cam
    if kind == "minibus":
        parts.append(box("Cabin", (L * 0.9, H * 0.5, W - 0.12),
                         (-L * 0.03, H * 1.05, 0), material="glass"))
        parts.append(box("Roof", (L * 0.92, 0.14, W),
                         (-L * 0.03, H * 1.32, 0), material=body_mat))
    else:
        parts.append(box("Cabin", (L * 0.52, H * 0.62, W - 0.16),
                         (-L * 0.06, H * 1.02, 0), material="glass"))
        parts.append(box("Hood", (L * 0.28, H * 0.42, W - 0.1),
                         (L * 0.33, H * 0.82, 0), material=body_mat))
    # Fenerler
    for s in (-1, 1):
        parts.append(box(f"Head{s}", (0.12, 0.28, 0.5),
                         (L * 0.5, H * 0.55, s * (W * 0.32)),
                         material="headlight"))
        parts.append(box(f"Tail{s}", (0.1, 0.24, 0.45),
                         (-L * 0.5, H * 0.55, s * (W * 0.32)),
                         material="taillight"))
    # Tampon
    parts.append(box("BumperF", (0.2, 0.3, W),
                     (L * 0.52, H * 0.32, 0), material="chrome"))
    parts.append(box("BumperR", (0.2, 0.3, W),
                     (-L * 0.52, H * 0.32, 0), material="chrome"))
    # Tekerlekler
    for wx in (-L * 0.32, L * 0.32):
        for wz in (-W * 0.5, W * 0.5):
            parts.append(cyl(f"Wheel{wx}{wz}", 0.42, 0.26,
                             (wx, 0.42, wz), rot=(math.radians(90), 0, 0),
                             material="tire", verts=12))
            parts.append(cyl(f"Hub{wx}{wz}", 0.18, 0.28,
                             (wx, 0.42, wz), rot=(math.radians(90), 0, 0),
                             material="chrome", verts=8))
    # Aynalar
    for s in (-1, 1):
        parts.append(box(f"Mirror{s}", (0.18, 0.14, 0.1),
                         (L * 0.22, H * 1.05, s * (W * 0.55 + 0.08)),
                         material="chrome"))
    # Taksi tabelası
    if kind == "taxi":
        parts.append(box("TaxiSign", (1.0, 0.3, 0.44),
                         (0, H * 1.32, 0), material="neon_cyan"))

    for p in parts:
        shade_flat(p)
    export_glb(parts, f"{name}.glb")


# ═══════════════════════════════════════════════════════════════════════════
# PROPS
# ═══════════════════════════════════════════════════════════════════════════
def build_street_lamp():
    clear_scene()
    parts = []
    parts.append(cyl("Post", 0.09, 5.4, (0, 2.7, 0), material="metal", verts=8))
    parts.append(cyl("Arm", 0.06, 1.5, (0.6, 5.3, 0),
                     rot=(0, math.radians(90), math.radians(-28)),
                     material="metal", verts=8))
    parts.append(box("Head", (0.7, 0.18, 0.42), (1.2, 5.45, 0), material="metal"))
    parts.append(box("Glow", (0.56, 0.08, 0.32), (1.2, 5.33, 0),
                     material="lamp_glow"))
    for p in parts:
        shade_flat(p)
    export_glb(parts, "street_lamp.glb")


def build_bicycle():
    clear_scene()
    parts = []
    for x in (-0.62, 0.62):
        parts.append(torus(f"Wheel{x}", 0.36, 0.045, (x, 0.4, 0),
                           rot=(math.radians(90), 0, 0), material="tire"))
        parts.append(cyl(f"Hub{x}", 0.05, 0.04, (x, 0.4, 0),
                         rot=(math.radians(90), 0, 0), material="chrome", verts=8))
    parts.append(box("Frame", (1.15, 0.06, 0.06), (0, 0.6, 0), material="building2"))
    parts.append(box("Post", (0.06, 0.48, 0.06), (0.28, 0.46, 0), material="building2"))
    parts.append(box("Handle", (0.06, 0.05, 0.46), (0.55, 0.78, 0), material="chrome"))
    parts.append(box("Seat", (0.26, 0.06, 0.16), (-0.5, 0.76, 0), material="shoe"))
    for p in parts:
        shade_flat(p)
    export_glb(parts, "bicycle.glb")


def build_hydrant():
    clear_scene()
    parts = []
    parts.append(cyl("Body", 0.16, 0.7, (0, 0.36, 0), material="hydrant", verts=10))
    parts.append(sphere("Top", 0.17, (0, 0.76, 0), material="hydrant",
                        segs=10, rings=6))
    parts.append(cyl("Nozzle", 0.08, 0.5, (0, 0.5, 0.18),
                     rot=(math.radians(90), 0, 0), material="hydrant", verts=8))
    parts.append(cyl("Base", 0.22, 0.1, (0, 0.05, 0), material="hydrant", verts=10))
    for p in parts:
        shade_flat(p)
    export_glb(parts, "hydrant.glb")


def build_dog():
    clear_scene()
    parts = []
    parts.append(box("Body", (0.85, 0.44, 0.34), (0, 0.42, 0), material="dog"))
    parts.append(box("Head", (0.30, 0.30, 0.28), (0.52, 0.56, 0), material="dog"))
    parts.append(box("Snout", (0.16, 0.14, 0.14), (0.72, 0.50, 0), material="dog"))
    parts.append(box("Nose", (0.06, 0.06, 0.08), (0.82, 0.52, 0), material="shoe"))
    for s in (-1, 1):
        parts.append(cone(f"Ear{s}", 0.07, 0.18, (0.46, 0.76, s * 0.09),
                          material="dog", verts=6))
    for lx in (-0.28, 0.28):
        for lz in (-0.12, 0.12):
            parts.append(box(f"Leg{lx}{lz}", (0.10, 0.42, 0.10),
                             (lx, 0.21, lz), material="dog"))
    parts.append(box("Tail", (0.30, 0.08, 0.08), (-0.55, 0.58, 0), material="dog"))
    for p in parts:
        shade_flat(p)
    export_glb(parts, "dog.glb")


def build_crate():
    clear_scene()
    parts = []
    parts.append(box("Crate", (0.9, 0.6, 0.9), (0, 0.3, 0), material="crate"))
    parts.append(box("Rim", (0.94, 0.08, 0.94), (0, 0.58, 0), material="veg_red"))
    # Sebzeler
    for i in range(6):
        x = -0.26 + (i % 3) * 0.26
        y = 0.66 + (i // 3) * 0.12
        parts.append(sphere(f"Veg{i}", 0.12, (x, y, 0),
                            material="veg_green" if i % 2 == 0 else "veg_red",
                            segs=8, rings=6))
    for p in parts:
        shade_flat(p)
    export_glb(parts, "crate.glb")


def build_cone():
    clear_scene()
    parts = []
    parts.append(cone("Cone", 0.30, 0.85, (0, 0.43, 0), material="orange", verts=10))
    parts.append(cyl("Base", 0.32, 0.06, (0, 0.03, 0), material="orange", verts=10))
    parts.append(cyl("Band", 0.20, 0.12, (0, 0.46, 0), material="cream", verts=10))
    for p in parts:
        shade_flat(p)
    export_glb(parts, "cone.glb")


# ═══════════════════════════════════════════════════════════════════════════
# ANA
# ═══════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    print("\n=== SON DİLİM — ASSET ÜRETİMİ ===\n")
    build_character()
    build_cake_box(open_lid=False)
    build_cake_box(open_lid=True)
    build_buildings()
    build_vehicle("taxi", "taxi")
    build_vehicle("minibus", "minibus")
    build_vehicle("sedan", "sedan")
    build_street_lamp()
    build_bicycle()
    build_hydrant()
    build_dog()
    build_crate()
    build_cone()
    print("\n=== TAMAMLANDI ===\n")
