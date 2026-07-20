extends Node
class_name MazeKit

# Geometry primitives shared by the three Backrooms zones (backrooms.gd, and the
# zone builders backrooms_zone2.gd / backrooms_zone3.gd).
#
# Lifted verbatim out of backrooms.gd when the level grew from one hub to three
# zones. Everything is static and takes an explicit parent, so a zone builder can
# hang geometry off itself while backrooms.gd keeps building at the scene root.
#
# ⚠️ make_material's NEGATIVE V scale is load-bearing: a positive uv1_scale.y
# renders the wallpaper upside-down on walls. Same trick as corridor.gd.

const TEX_DIR := "res://assets/textures/level_backrooms/"


static func make_material(tex_path: String, uv_scale: Vector2, fallback: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.95
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(uv_scale.x, -uv_scale.y, uv_scale.x)
	else:
		mat.albedo_color = fallback
	return mat


static func wall_material() -> StandardMaterial3D:
	return make_material(TEX_DIR + "backrooms_wallpaper_albedo.png",
		Vector2(1.0, 1.0 / 3.0), Color(0.78, 0.70, 0.32))


static func floor_material() -> StandardMaterial3D:
	return make_material(TEX_DIR + "backrooms_carpet_albedo.png",
		Vector2(0.4, 0.4), Color(0.32, 0.28, 0.14))


static func ceiling_material() -> StandardMaterial3D:
	return make_material("", Vector2.ONE, Color(0.55, 0.52, 0.42))


# Axis-aligned box. center = world centre, size = full extents.
static func box(parent: Node, box_name: String, center: Vector3, size: Vector3,
		mat: Material) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = box_name
	b.size = size
	b.position = center
	b.use_collision = true
	if mat:
		b.material = mat
	parent.add_child(b)
	return b


# Floor + ceiling slab pair spanning a rectangle on the xz plane.
static func slab(parent: Node, prefix: String, center_xz: Vector3, size_xz: Vector3,
		height: float, thickness: float, floor_mat: Material, ceil_mat: Material) -> void:
	box(parent, prefix + "Floor", Vector3(center_xz.x, -thickness / 2.0, center_xz.z),
		Vector3(size_xz.x, thickness, size_xz.z), floor_mat)
	box(parent, prefix + "Ceil", Vector3(center_xz.x, height + thickness / 2.0, center_xz.z),
		Vector3(size_xz.x, thickness, size_xz.z), ceil_mat)


static func wall(parent: Node, wall_name: String, center_xz: Vector3, size_xz: Vector3,
		height: float, mat: Material) -> CSGBox3D:
	return box(parent, wall_name, Vector3(center_xz.x, height / 2.0, center_xz.z),
		Vector3(size_xz.x, height, size_xz.z), mat)


# Recessed flickering fluorescent: emissive panel + the light itself. Returns
# { light, base } so the caller can register it for the per-frame flicker pass.
static func light_strip(parent: Node, pos: Vector3, height: float,
		energy: float = 1.1, lrange: float = 6.0) -> Dictionary:
	var panel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.06, 0.5)
	panel.mesh = bm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.95, 0.92, 0.75)
	pm.emission_enabled = true
	pm.emission = Color(1.0, 0.95, 0.7)
	pm.emission_energy_multiplier = 1.6
	panel.set_surface_override_material(0, pm)
	panel.position = Vector3(pos.x, height - 0.05, pos.z)
	parent.add_child(panel)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.93, 0.65)
	light.light_energy = energy
	light.omni_range = lrange
	light.position = Vector3(pos.x, height - 0.3, pos.z)
	parent.add_child(light)

	return { "light": light, "base": energy, "panel": panel, "mat": pm }


# Area3D of the given script class covering a box volume. Used for every
# DarkZone / DreadZone / CalmZone / CorridorEvent the zones drop.
static func zone_box(parent: Node, zone: Area3D, center: Vector3, size: Vector3,
		zone_name: String = "") -> Area3D:
	if zone_name != "":
		zone.name = zone_name
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	zone.add_child(col)
	zone.position = center
	parent.add_child(zone)
	return zone
