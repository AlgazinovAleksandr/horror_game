class_name WallSconce
extends StaticBody3D

# One of THE NIGHTMARE's seven sconces (DUNGEON_NIGHTMARES.md §B3, §B5).
#
# Light it with a burning candle and it becomes a PERMANENT CalmZone island (decay
# x2.5) that stays lit for the rest of the night. Seven of them are the level's
# escalation clock — and the level physically gets SAFER as you progress (more
# light, more calm islands) while the roster escalates to compensate. That is DN's
# "same objects, different rules" teaching structure compressed into one night.
#
# ⚠️ Requires a LIT CANDLE, not merely the E key. The level owns that check and the
# refusal message — this prop only reports that E was pressed, the same
# prop-emits / level-decides split as cellar_gate.gd and fungal_barrier.gd.
#
# ⚠️ Mounted with wall_point(room, side, y, 0.16) on a side the generator has
# guaranteed carries NO doorway. wall_point() returns the wall CENTRE, which is
# exactly where a doorway sits, and a collider there silently seals the room — the
# Records warning sign did this in the Lab (§B6 step 7).

signal lit

# Surface GRAIN only — never a picture of a sconce. shared/rusted_iron.png is the
# same texture beartrap.gd uses for exactly this purpose.
const IRON_TEX := "res://assets/textures/shared/rusted_iron.png"
const CALM_RADIUS := 5.5
const LIGHT_RANGE := 7.0
const LIGHT_ENERGY := 0.85
const LIGHT_COLOR := Color(1.0, 0.74, 0.42)

var is_lit: bool = false

var _light: OmniLight3D
var _calm: Area3D
var _flame: MeshInstance3D
var _flicker: float = 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()


func _build() -> void:
	# ⚠️ REAL GEOMETRY, NO PHOTO. dn_sconce.png / dn_sconce_lit.png are generated with
	# their own background baked in, so on a quad they render as a small framed
	# PICTURE bolted to the wall — visibly a poster, with a pale border, never an
	# object. That is Issue 35 verbatim ("a wall prop whose artwork contained a
	# picture of the wall behind it"), and its documented resolution is the one
	# applied here and to intro_room.gd's wheelchair and kontur.gd's mailbox: stop
	# asking a texture to do a mesh's job. rotary_phone.gd remains the proof that in
	# this project the SILHOUETTE carries a prop and the art does not.
	#
	# An oil sconce is four primitives: a back plate on the wall, an arm out of it, a
	# cup on the arm, and a flame in the cup.
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.12, 0.115)
	iron.roughness = 0.95
	iron.metallic = 0.35
	if ResourceLoader.exists(IRON_TEX):
		var t: Texture2D = load(IRON_TEX)
		if t != null:
			iron.albedo_texture = t
			iron.albedo_color = Color(0.42, 0.39, 0.35)
			iron.uv1_scale = Vector3(3.0, 3.0, 3.0)

	var plate := MeshInstance3D.new()
	plate.name = "SconcePlate"
	var pm := BoxMesh.new()
	pm.size = Vector3(0.16, 0.30, 0.04)
	plate.mesh = pm
	plate.set_surface_override_material(0, iron)
	plate.position = Vector3(0, 0, 0.02)
	add_child(plate)

	var arm := MeshInstance3D.new()
	arm.name = "SconceArm"
	var am := BoxMesh.new()
	am.size = Vector3(0.05, 0.05, 0.22)
	arm.mesh = am
	arm.set_surface_override_material(0, iron)
	arm.position = Vector3(0, -0.02, 0.14)
	arm.rotation.x = -0.35
	add_child(arm)

	var cup := MeshInstance3D.new()
	cup.name = "SconceCup"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.085
	cm.bottom_radius = 0.045
	cm.height = 0.09
	cup.mesh = cm
	cup.set_surface_override_material(0, iron)
	cup.position = Vector3(0, 0.06, 0.25)
	add_child(cup)

	# Hidden until lit. Dark albedo + emission under 1.0: above 1.0 it clamps to
	# flat pure white with no detail (Issue 21), and a bright albedo next to its own
	# point light blows out regardless.
	_flame = MeshInstance3D.new()
	_flame.name = "SconceFlame"
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.15
	_flame.mesh = sm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.18, 0.05)
	fm.emission_enabled = true
	fm.emission = LIGHT_COLOR
	fm.emission_energy_multiplier = 0.8
	_flame.material_override = fm
	_flame.position = Vector3(0, 0.14, 0.25)
	_flame.visible = false
	add_child(_flame)

	_light = OmniLight3D.new()
	_light.name = "SconceLight"
	_light.omni_range = LIGHT_RANGE
	_light.omni_attenuation = 1.5
	_light.light_color = LIGHT_COLOR
	_light.light_energy = 0.0
	_light.visible = false
	_light.position = Vector3(0, 0.18, 0.28)
	add_child(_light)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.5, 0.45)
	col.shape = shape
	col.position = Vector3(0, 0, 0.15)
	add_child(col)


func _process(delta: float) -> void:
	if not is_lit:
		return
	_flicker += delta
	_light.light_energy = LIGHT_ENERGY * (1.0 + 0.05 * sin(_flicker * 7.4)
		+ 0.03 * sin(_flicker * 4.1))


func interact() -> void:
	if is_lit:
		return
	# The level decides whether the player has a burning candle. Emitting either
	# way keeps this prop ignorant of the candle system entirely.
	lit.emit()


# Called by the level once it has confirmed a lit candle.
func light_it() -> void:
	if is_lit:
		return
	is_lit = true
	_flame.visible = true
	_light.visible = true
	_light.light_energy = 0.0
	var tw := create_tween()
	tw.tween_property(_light, "light_energy", LIGHT_ENERGY, 1.2)

	# A permanent CalmZone island: decay x2.5 for the rest of the night. This is the
	# reward loop — and the reason the level gets physically safer as it escalates.
	_calm = Area3D.new()
	_calm.name = "SconceCalm"
	_calm.set_script(load("res://scripts/calm_zone.gd"))
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = CALM_RADIUS
	cs.shape = sphere
	_calm.add_child(cs)
	# ⚠️ Parented to the LEVEL, not to this prop. An Area3D on a body that is itself
	# on layer 1 is fine, but keeping the zone a sibling keeps its transform simple
	# and matches torch_3d.gd's CalmZone convention.
	_calm.position = global_position
	get_parent().add_child(_calm)


func can_interact() -> bool:
	return not is_lit
