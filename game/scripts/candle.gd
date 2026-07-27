class_name Candle
extends Node3D

# The player's light in THE NIGHTMARE (DUNGEON_NIGHTMARES.md §B5).
#
# The candle REPLACES the flashlight — dungeon.gd calls player.kill_flashlight() at
# entry, so F only clicks. That is not an arbitrary nerf: the protocol note says
# "we cannot give you anything that runs on our power down there", and coming off
# The Breach — where the flashlight was a WEAPON — its confiscation is the
# escalation.
#
# Two verbs, and they are not the same verb:
#   F  light / blow out   (consumes a candle to light; blowing BANKS the remainder)
#   C  spark              (free, unlimited, no cooldown)
#
# ⚠️ Blowing it out banks the remaining seconds rather than wasting them. DN wastes
# them, and §B11 cuts that deliberately: the punishment is silent, invisible, and
# arrives up to a minute later at an unpredictable place — an unteachable gotcha.
# The real cost of relighting is the 1.2 s spark dip and the noise it makes.
#
# ⚠️ There is NO globally correct light posture, and that is the whole level:
#   Child          suppressed by a lit candle          ✅
#   Weeping Frames easier to see, therefore avoid      ✅
#   Kneeling Man   dispelled                           ✅
#   Matron         detects you from 9 m instead of 5 m ❌
#   Still Ones     visible ✅ / advance one step per spark ❌ / spark within 2 m FATAL
#   Hollow One     the candle does NOTHING ⚠️ — a spark is the only way to see it
# By six sconces the correct posture has inverted. The player who learned "candle
# good" in the first five minutes has to unlearn it in the last five.

signal burned_out
signal lit_changed(is_lit: bool)
signal sparked

const BURN_SECONDS := 60.0        # DN2's exact duration
const CARRY_CAP := 4              # between DN2's 6 and the Remaster's 3
# ⚠️ Retuned from the spec's literal numbers after measuring (see the screenshots
# in the build report). §B5 asks for energy 1.0 and attenuation 2.4 at range 4.5,
# which in this project's lighting — ambient 0.02, no glow, no fog — renders a
# chamber you are standing in as very nearly pure black: the near floor is lit and
# nothing else, so there is no "edge of visibility" to be frightened of, only an
# unreadable screen.
# Energy is raised and the falloff curve softened while the RANGE is untouched at
# 4.5 m. Range is what enforces §B7's "you cannot see the far wall"; attenuation
# only controls how abruptly the light dies inside it, and 2.4 was so steep that
# the lit volume was barely a metre across. A light's energy is not subject to the
# emission-clamp rule (that applies to MATERIALS) — 2.2 is an ordinary value.
const ENERGY_START := 2.2
const ENERGY_END := 0.8           # it dims the whole time it burns
const LIGHT_RANGE := 4.5
const LIGHT_ATTEN := 1.4
const LIGHT_COLOR := Color(1.0, 0.78, 0.45)

const SPARK_SECONDS := 0.25
const SPARK_RANGE := 9.0
const SPARK_ENERGY := 1.4
# ⭐ The after-dip. DN: "after that, it gets darker than before, until your vision is
# back to normal." This is what makes a FREE action feel expensive, and it is why DN
# players ration something that costs no resource at all.
const SPARK_DIP_SECONDS := 1.2

var candles: int = CARRY_CAP
var burning: bool = false
var remaining: float = BURN_SECONDS

var _light: OmniLight3D
var _flame: MeshInstance3D
var _spark_light: OmniLight3D
var _spark_t: float = 0.0
var _dip_t: float = 0.0
var _flicker: float = 0.0
var _first_burnout_shown := false


func _ready() -> void:
	_light = OmniLight3D.new()
	_light.name = "CandleLight"
	_light.omni_range = LIGHT_RANGE
	_light.omni_attenuation = LIGHT_ATTEN
	_light.light_color = LIGHT_COLOR
	_light.light_energy = 0.0
	_light.visible = false
	# ⚠️ No shadow. The flashlight casts (all nine level scenes enable it) but this
	# light sits INSIDE the player's collision capsule and would self-shadow into a
	# black disc. Darkness here comes from range falloff, not from occlusion.
	_light.shadow_enabled = false
	add_child(_light)

	# ⚠️ A held CANDLE, not a floating flame. The first version was a single 0.025 m
	# emissive sphere 0.42 m from the camera, which subtends ~7 degrees and rendered
	# as a large flat yellow egg in the corner of the screen with nothing to explain
	# it. A wax stick under it costs two primitives and turns the same pixels into a
	# recognisable object — the rotary_phone.gd lesson that in this project the
	# SILHOUETTE carries a prop and the art does not.
	_flame = MeshInstance3D.new()
	_flame.name = "CandleHeld"
	var stick := CylinderMesh.new()
	stick.top_radius = 0.016
	stick.bottom_radius = 0.019
	stick.height = 0.17
	_flame.mesh = stick
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.86, 0.83, 0.72)
	wax.roughness = 0.85
	_flame.material_override = wax
	_flame.position = Vector3(0.34, -0.40, -0.72)
	_flame.rotation = Vector3(0.12, 0.0, -0.10)
	_flame.visible = false
	add_child(_flame)

	var wick := MeshInstance3D.new()
	wick.name = "Flame"
	var sphere := SphereMesh.new()
	sphere.radius = 0.016
	sphere.height = 0.05
	wick.mesh = sphere
	var mat := StandardMaterial3D.new()
	# Dark albedo, emission under 1.0. Above 1.0 it clamps to flat pure white with
	# no detail — Linear tonemap, exposure 1.0, no glow anywhere here (Issue 21).
	mat.albedo_color = Color(0.35, 0.20, 0.06)
	mat.emission_enabled = true
	mat.emission = LIGHT_COLOR
	mat.emission_energy_multiplier = 0.75
	wick.material_override = mat
	wick.position = Vector3(0, 0.12, 0)
	_flame.add_child(wick)

	_spark_light = OmniLight3D.new()
	_spark_light.name = "SparkLight"
	_spark_light.omni_range = SPARK_RANGE
	_spark_light.omni_attenuation = 1.6
	_spark_light.light_color = Color(0.95, 0.9, 0.8)
	_spark_light.light_energy = 0.0
	_spark_light.visible = false
	_spark_light.shadow_enabled = false
	add_child(_spark_light)


func _process(delta: float) -> void:
	if burning:
		remaining -= delta
		if remaining <= 0.0:
			_extinguish(true)
		else:
			var t: float = 1.0 - (remaining / BURN_SECONDS)
			var base: float = lerpf(ENERGY_START, ENERGY_END, t)
			_flicker += delta
			# Two out-of-phase sines: an organic guttering rather than a strobe.
			var flick: float = 1.0 + 0.06 * sin(_flicker * 11.0) + 0.04 * sin(_flicker * 6.3)
			_light.light_energy = base * flick

	if _spark_t > 0.0:
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_light.visible = false
			_spark_light.light_energy = 0.0
			_dip_t = SPARK_DIP_SECONDS
		else:
			_spark_light.light_energy = SPARK_ENERGY * (_spark_t / SPARK_SECONDS)
	elif _dip_t > 0.0:
		_dip_t -= delta


# 0 while normal, rising to 1 at the deepest part of the post-spark dip. dungeon.gd
# multiplies the world ambient down by this — the "darker than before" beat.
func dip_ratio() -> float:
	if _dip_t <= 0.0:
		return 0.0
	return _dip_t / SPARK_DIP_SECONDS


func can_light() -> bool:
	return not burning and (candles > 0 or remaining > 0.5)


# F. Lights a fresh candle, or blows out the one that is burning (banking the rest).
func toggle() -> bool:
	if burning:
		_extinguish(false)
		return false
	if remaining > 0.5:
		# Relighting a banked stub — costs nothing but the noise and the dip.
		burning = true
	elif candles > 0:
		candles -= 1
		remaining = BURN_SECONDS
		burning = true
	else:
		return false
	_light.visible = true
	_flame.visible = true
	lit_changed.emit(true)
	return true


func _extinguish(burned: bool) -> void:
	burning = false
	if burned:
		remaining = 0.0
	_light.visible = false
	_light.light_energy = 0.0
	_flame.visible = false
	lit_changed.emit(false)
	if burned:
		burned_out.emit()


# C. Free, unlimited. One frame of truth, then it is darker than it was.
func spark() -> void:
	_spark_t = SPARK_SECONDS
	_spark_light.visible = true
	_spark_light.light_energy = SPARK_ENERGY
	sparked.emit()


func is_sparking() -> bool:
	return _spark_t > 0.0


func add_candle() -> bool:
	if candles >= CARRY_CAP:
		return false
	candles += 1
	return true


func mark_burnout_shown() -> void:
	_first_burnout_shown = true


func burnout_shown() -> bool:
	return _first_burnout_shown
