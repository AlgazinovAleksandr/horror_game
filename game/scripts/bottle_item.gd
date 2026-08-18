extends StaticBody3D
class_name BottleItem

# KONTUR Gate 2 — one bottle on the communal-kitchen shelf. Picking one up carries
# it; the fungal barrier asks what you are holding. Only "vinegar" works (the L2
# House TV card is the hint). Self-building: a glass body + a paper label quad.
#
# Layer 2 / mask 0 like note.gd, so the player can walk through the shelf line
# rather than bumping into it — the interaction ray still hits it.

signal taken(kind: String)

const INTERACTABLE_LAYER := 2
const BODY_H := 0.26
const BODY_R := 0.045

# ⚠️ THE THREE BOTTLES USED TO BE THE SAME CYLINDER (2026-08-18). Gate 2's whole task is
# "pick the right one of three", and until this pass the only thing distinguishing them
# was a 9 x 12 cm label carrying a 1.733x-squashed word on an opaque photographic
# backdrop. Issue 35's rule applies to a shelf as much as to a bed: SILHOUETTE carries a
# prop, art does not — three identical cylinders read as three identical cylinders from
# any distance at which the words are not yet legible.
#
# ⚠️ This changes NOTHING about the answer. Vinegar is still vinegar, the hint is still
# the House TV card, and shape alone tells you nothing about which agent dissolves O-41 —
# a player who never found the hint still has to guess, and still pays a strike for it.
# What changed is that they can now tell they are looking at three DIFFERENT things.
#
#   flask   tall, slim, corked, dark green glass     (vinegar)
#   jug     squat, shouldered, handled, opaque       (bleach)
#   carboy  short, wide, wide-mouthed, clear         (water)
const PROFILES := {
	# radius_bottom, radius_top, height_mul, neck_r, neck_h, cap, handle, tint
	"flask":  {"rb": 0.040, "rt": 0.022, "hm": 1.00, "neck": 0.019, "neck_h": 0.055,
		"cap": true, "handle": false, "tint": Color(0.16, 0.26, 0.15), "rough": 0.18},
	"jug":    {"rb": 0.058, "rt": 0.050, "hm": 0.82, "neck": 0.028, "neck_h": 0.030,
		"cap": true, "handle": true, "tint": Color(0.72, 0.72, 0.68), "rough": 0.62},
	"carboy": {"rb": 0.062, "rt": 0.058, "hm": 0.62, "neck": 0.046, "neck_h": 0.016,
		"cap": false, "handle": false, "tint": Color(0.52, 0.58, 0.60), "rough": 0.12},
}

@export var kind: String = "vinegar"
@export var label_path: String = ""
@export var profile: String = "flask"

var _taken: bool = false


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	_build()


func _build() -> void:
	build_visual(self, profile, label_path)

	# A generous collider — the bottle mesh is small and the interaction ray is
	# unforgiving on thin geometry (Issue 2).
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.22, 0.36, 0.22)
	col.shape = shape
	col.position = Vector3(0, BODY_H / 2.0, 0)
	add_child(col)


# ⚠️ STATIC, and the collider is deliberately NOT part of it (2026-08-18). The
# Perëkozhnik wears one of these as a disguise (`mimic_shell.gd`), and a mimic must be
# built from the SAME geometry as the thing it is imitating — the moment the two are
# built by two functions they start to drift, and "spot the odd one out" stops being a
# fair question. The caller supplies its own collider, because a real bottle and a mimic
# want different ones.
static func build_visual(parent: Node3D, profile_name: String, label: String) -> void:
	var p: Dictionary = PROFILES.get(profile_name, PROFILES["flask"])
	var body_h: float = BODY_H * float(p["hm"])

	var glass := StandardMaterial3D.new()
	glass.albedo_color = p["tint"]
	glass.roughness = float(p["rough"])
	glass.metallic = 0.12

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = float(p["rt"])
	cyl.bottom_radius = float(p["rb"])
	cyl.height = body_h
	mesh.mesh = cyl
	mesh.material_override = glass
	mesh.position = Vector3(0, body_h / 2.0, 0)
	parent.add_child(mesh)

	# The neck — the single part that most separates a flask from a jug at a glance.
	var neck_h: float = float(p["neck_h"])
	var neck := MeshInstance3D.new()
	var ncyl := CylinderMesh.new()
	ncyl.top_radius = float(p["neck"])
	ncyl.bottom_radius = float(p["neck"]) * 1.15
	ncyl.height = neck_h
	neck.mesh = ncyl
	neck.material_override = glass
	neck.position = Vector3(0, body_h + neck_h / 2.0, 0)
	parent.add_child(neck)

	if bool(p["cap"]):
		var cap_mat := StandardMaterial3D.new()
		cap_mat.albedo_color = Color(0.24, 0.19, 0.13) if profile_name == "flask" \
			else Color(0.14, 0.15, 0.14)
		cap_mat.roughness = 0.85
		var cap := MeshInstance3D.new()
		var ccyl := CylinderMesh.new()
		ccyl.top_radius = float(p["neck"]) * 1.25
		ccyl.bottom_radius = float(p["neck"]) * 1.25
		ccyl.height = 0.022
		cap.mesh = ccyl
		cap.material_override = cap_mat
		cap.position = Vector3(0, body_h + neck_h + 0.011, 0)
		parent.add_child(cap)

	if bool(p["handle"]):
		# A torus laid in the XY plane on the bottle's -x side: the jug's whole read.
		var handle := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.020
		tor.outer_radius = 0.036
		handle.mesh = tor
		handle.material_override = glass
		handle.rotation.x = PI / 2.0
		handle.position = Vector3(-float(p["rb"]) - 0.012, body_h * 0.72, 0)
		parent.add_child(handle)

	if label != "" and ResourceLoader.exists(label):
		var tex: Texture2D = load(label)
		# ⚠️ Sized from the ARTWORK, never from the bottle. The three labels are three
		# different shapes (1.975 / 1.360 / 1.971) because they are three different
		# products; forcing all three onto one quad is what squashed the words 1.733x.
		var aspect: float = float(tex.get_width()) / float(tex.get_height())
		# ⚠️ A FLOOR, not just a proportion. Scaled purely off the body radius the slim
		# flask — which is the RIGHT bottle — got the smallest label of the three, i.e.
		# the level's answer was the hardest word on the shelf to read.
		var lw: float = maxf(float(p["rb"]) * 1.90, 0.088)
		var lh: float = lw / aspect
		var max_h: float = body_h * 0.62
		if lh > max_h:
			lh = max_h
			lw = lh * aspect
		var lab := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(lw, lh)
		lab.mesh = quad
		var lmat := StandardMaterial3D.new()
		lmat.albedo_texture = tex
		lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# The cropped labels are real RGBA cutouts now (tools/crop_kontur_art.py), so
		# this flag finally does something: before, all three were 8-bit RGB and the
		# generator's backdrop rendered as an opaque rectangle stuck to the glass.
		lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lab.material_override = lmat
		# Lift the label off the glass so it never z-fights with the cylinder.
		lab.position = Vector3(0, body_h * 0.48, float(p["rb"]) + 0.004)
		parent.add_child(lab)


func interact() -> void:
	if _taken:
		return
	_taken = true
	taken.emit(kind)
	queue_free()
