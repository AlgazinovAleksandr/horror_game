extends StaticBody3D
class_name OfferingPedestal

# KONTUR Gate 3 — the bait. A keycard glowing on a lit pedestal, deliberately
# identical in read to the Lab keycard the player has spent five levels being
# trained to grab. The exit is already open; the correct play is to walk past.
#
# The pedestal reports the grab and nothing else — kontur.gd scores it, and the
# level's exit sensor scores the abstain.

signal taken

const INTERACTABLE_LAYER := 2
const CARD_TEX := "res://assets/textures/level_5_kontur/kontur_keycard.png"

var _taken: bool = false
var _card: MeshInstance3D
var _t: float = 0.0


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	_build()


func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.16, 0.16, 0.17)
	stone.roughness = 0.9

	var plinth := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(0.5, 1.0, 0.5)
	plinth.mesh = pbox
	plinth.material_override = stone
	plinth.position = Vector3(0, 0.5, 0)
	add_child(plinth)

	var card_mat := StandardMaterial3D.new()
	card_mat.albedo_color = Color(0.75, 0.85, 0.95)
	card_mat.emission_enabled = true
	card_mat.emission = Color(0.45, 0.75, 1.0)
	# ⚠️ Was 2.2 — above 1.0 clamps to flat pure white under Linear tonemap with no
	# glow, so the bait card was a featureless white lozenge (Issue 21). It still has
	# to glow invitingly; 0.9 does that without erasing the art.
	card_mat.emission_energy_multiplier = 0.9

	_card = MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(0.16, 0.10, 0.012)
	_card.mesh = cbox
	_card.material_override = card_mat
	_card.position = Vector3(0, 1.12, 0)
	_card.rotation = Vector3(deg_to_rad(-20.0), 0, 0)
	add_child(_card)

	# Card art on a quad on the up-tilted face — a texture on the box itself would
	# render a magnified crop (Issue 24). Guarded, so the gate works untextured too.
	if ResourceLoader.exists(CARD_TEX):
		var face := MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = Vector2(0.16, 0.10)
		face.mesh = fq
		var fmat := StandardMaterial3D.new()
		var tex := load(CARD_TEX)
		fmat.albedo_texture = tex
		fmat.emission_enabled = true
		fmat.emission_texture = tex
		fmat.emission_energy_multiplier = 0.7
		face.set_surface_override_material(0, fmat)
		face.position = Vector3(0, 0, 0.009)
		_card.add_child(face)

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.55, 0.8, 1.0)
	glow.light_energy = 1.1
	glow.omni_range = 4.0
	glow.position = Vector3(0, 1.5, 0)
	add_child(glow)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 1.25, 0.5)
	col.shape = shape
	col.position = Vector3(0, 0.62, 0)
	add_child(col)


func _process(delta: float) -> void:
	if _taken or not _card:
		return
	# A slow hover — it should look like it wants to be picked up.
	_t += delta
	_card.position.y = 1.12 + sin(_t * 1.6) * 0.03


func interact() -> void:
	if _taken:
		return
	_taken = true
	taken.emit()
	if _card:
		_card.queue_free()
