extends CanvasLayer

# Autoload singleton: JournalUI. Press TAB to re-read any note you have already found.
#
# ─────────────────────────────────────────────────────────────────────────────────
# WHY THIS EXISTS
#
# The game deliberately hides answers across level boundaries — KONTUR's eight gates
# are all hinted in levels 1-4, and the roster code now lives on two notes in the
# Backrooms Flood (BACKLOG #24). That design only works if "I read that somewhere" can
# be acted on. Before this, it could not: a note was a one-time modal, and the reported
# consequence was "I cannot pass the Backrooms because I skipped important notes. If I
# go to level 1, I will need to pass all the levels from the beginning" (BACKLOG #30).
#
# Per-level progress snapshots fix the walking; this fixes the remembering, and it is
# the cheaper half by a wide margin.
#
# ⚠️ TRAP NOTES ARE NEVER ARCHIVED. note.gd only records non-trap notes, because a trap
# note is read-to-die (+12 panic/s while open) and a safely re-readable copy would hand
# that mechanic a free loophole: open it here, read to the end, learn the text, take no
# damage. The recording happens on OPEN, matching note.gd's `read` signal — finding a
# note is what earns you the copy, not surviving it.
#
# Built entirely in GDScript with no .tscn, for the reason note_ui.gd's header gives:
# attaching an autoload to a scene file needs extra project config that can desync.

const PANEL_SIZE := Vector2(940, 560)
const LIST_WIDTH := 300.0

var is_open: bool = false

var _root: Control
var _list: ItemList
var _text: RichTextLabel
var _empty_hint: Label
var _block_close: bool = false
var _entries: Array = []          # snapshot of GameState.journal at open time

const LEVEL_NAMES := {
	0: "INTRO", 1: "THE LAB", 2: "THE HOUSE", 3: "THE CORRIDOR",
	4: "THE BACKROOMS", 5: "KONTUR", 6: "THE BREACH", 7: "THE VOID", 8: "—",
}


func _ready() -> void:
	layer = 49          # just under NoteUI (50), well under Screamer (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# CenterContainer, not PRESET_CENTER — that preset anchors a control's TOP-LEFT to
	# the screen centre and drops the panel into the bottom-right quadrant (Issue 4).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.07, 0.97)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.3, 0.25)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "RECOVERED DOCUMENTS"
	title.add_theme_color_override("font_color", Color(0.85, 0.80, 0.72))
	title.add_theme_font_size_override("font_size", 20)
	outer.add_child(title)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(split)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", 14)
	_list.item_selected.connect(_on_selected)
	split.add_child(_list)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.scroll_active = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_color_override("default_color", Color(0.92, 0.88, 0.80))
	_text.add_theme_font_size_override("normal_font_size", 17)
	split.add_child(_text)

	_empty_hint = Label.new()
	_empty_hint.text = "Nothing recovered yet. Notes you read are kept here."
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.add_theme_color_override("font_color", Color(0.5, 0.47, 0.43))
	outer.add_child(_empty_hint)

	var hint := Label.new()
	hint.text = "[ TAB or ESC to close ]"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38))
	hint.add_theme_font_size_override("font_size", 14)
	outer.add_child(hint)

	_root.visible = false


# Refuses rather than queues. Opening on top of a note, a lock, the maze minigame or a
# screamer would fight another system for the pause and the mouse mode — and opening
# while the player is frozen in a beartrap escape would be a free pause in the middle
# of a timed QTE.
func can_open() -> bool:
	if is_open or NoteUI.is_open or get_tree().paused:
		return false
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("is_input_frozen") and p.is_input_frozen():
		return false
	return true


func open_journal() -> void:
	if not can_open():
		return
	_entries = GameState.journal.duplicate()
	_list.clear()
	for e in _entries:
		var lvl: int = int(e.get("level", 0))
		_list.add_item("%s — %s" % [LEVEL_NAMES.get(lvl, "?"), e.get("title", "note")])
	_empty_hint.visible = _entries.is_empty()
	_text.text = ""
	if not _entries.is_empty():
		_list.select(0)
		_on_selected(0)

	_root.visible = true
	is_open = true
	_block_close = true       # the same frame's TAB must not close it again (Issue 3)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	set_deferred("_block_close", false)


func _on_selected(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	_text.text = String(_entries[index].get("text", ""))


func _process(_delta: float) -> void:
	# Same tree-pause invariant every pause-owning UI in this project carries: if we are
	# open but the tree is NOT paused, a screamer fired and owns the scene now — drop
	# the overlay silently rather than survive the reload (Issue 9).
	if is_open and not get_tree().paused:
		_root.visible = false
		is_open = false


func _unhandled_input(event: InputEvent) -> void:
	if is_open:
		if not _block_close and (event.is_action_pressed("journal")
				or event.is_action_pressed("ui_cancel")):
			_close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("journal"):
		open_journal()
		get_viewport().set_input_as_handled()


func _close() -> void:
	_root.visible = false
	is_open = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
