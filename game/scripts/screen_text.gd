extends Node
class_name ScreenText

# Transient on-screen text, in one place.
#
# Five separate hand-rolled "CanvasLayer + Label + fade + clean up" implementations
# had accumulated (kontur `_notice`, level_1 `_show_caption`, backrooms
# `_show_progress_text`, door `_show_locked_feedback`, main_menu's blood labels).
# This is the shared version; new call sites use it.
#
# ⚠️ Every helper here parents its CanvasLayer to the TREE ROOT and cleans up via a
# CONNECTED timer, never an awaited one. An awaited timer dies with the node that
# started it, so a label spawned by a level that then unloads would leak forever
# (Issue 6). Parenting to the root also means a scene change doesn't yank the text
# mid-fade — which matters for `scrawl()`, whose whole job is to survive one.

# The project's established blood-red. main_menu.gd writes its scrawled flavour lines
# in this colour; the accusation after a KONTUR banishment matches it deliberately.
const BLOOD := Color(0.72, 0.04, 0.04)


# A short centred message. The strike/notice register.
static func toast(tree: SceneTree, text: String, color: Color = Color(1, 1, 1),
		seconds: float = 2.2, font_size: int = 30) -> void:
	var canvas := _layer(tree)
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	_outline(lbl)
	canvas.add_child(lbl)
	_fade(tree, canvas, lbl, 0.25, seconds, 0.6)


# A subtitle low on the screen, for spoken lines.
static func caption(tree: SceneTree, text: String, seconds: float = 4.0) -> void:
	var canvas := _layer(tree)
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.82, 0.84, 0.78))
	_outline(lbl)
	lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl.offset_top = -140.0
	lbl.offset_bottom = -60.0
	canvas.add_child(lbl)
	_fade(tree, canvas, lbl, 0.5, seconds, 1.0)


# Blood-red, hand-daubed, slightly crooked. Used where the game speaks to the player
# rather than the fiction speaking to Subject 47: the banishment accusation, and the
# escort corridor's lie.
static func scrawl(tree: SceneTree, text: String, seconds: float = 5.0,
		font_size: int = 54) -> void:
	var canvas := _layer(tree)
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_color_override("font_color", BLOOD)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_constant_override("line_spacing", 14)
	_outline(lbl, 10)
	# The tilt is the whole trick: the project has no handwriting font, but a few
	# degrees off true reads as daubed rather than printed. Same device main_menu.gd
	# uses for its blood notes.
	lbl.pivot_offset = lbl.size / 2.0
	lbl.rotation = randf_range(-0.035, 0.035)
	canvas.add_child(lbl)
	_fade(tree, canvas, lbl, 0.6, seconds, 1.4)


# ---------------------------------------------------------------- internals

static func _layer(tree: SceneTree) -> CanvasLayer:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	# PROCESS_MODE_ALWAYS: a scare pauses nothing, but a note might, and text that
	# freezes mid-fade looks broken.
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(canvas)
	return canvas


static func _outline(lbl: Label, size: int = 6) -> void:
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", size)


static func _fade(tree: SceneTree, canvas: CanvasLayer, lbl: Label,
		fade_in: float, hold: float, fade_out: float) -> void:
	lbl.modulate.a = 0.0
	var t := canvas.create_tween()
	t.tween_property(lbl, "modulate:a", 1.0, fade_in)
	t.tween_interval(hold)
	t.tween_property(lbl, "modulate:a", 0.0, fade_out)
	# Connected, not awaited — see the header note.
	t.finished.connect(canvas.queue_free)
