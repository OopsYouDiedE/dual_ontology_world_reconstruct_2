extends RefCounted
## Unified movement and camera feel math shared by Expedition-01 and RoguePlayer.
## Keeps acceleration curves, stride pacing, aim scaling, and landing damping
## consistent across the lobby/rogue wing and the first-person expedition.

const ST_QUIET := 0
const ST_WALK := 1
const ST_RUN := 2

const EXPEDITION_SPEEDS := [1.55, 3.8, 6.4]
const STRIDE_LENGTHS := [0.68, 0.92, 1.24]

const ACCEL_GROUND := 26.0
const ACCEL_TURN := 52.0
const ACCEL_STOP := 34.0
const ACCEL_QUIET := 44.0
const AIR_CONTROL := 0.20

const AIM_SENS_SCALE := 0.45
const AIM_BREATH_SCALE := 0.42
const LAND_MIN_SPEED := 3.0
const STEP_ABSORB_MIN := 0.04
const STEP_ABSORB_MAX := 0.65

static func exp_damp(rate: float, dt: float) -> float:
	if dt <= 0.0:
		return 1.0
	return 1.0 - exp(-rate * dt)

static func step_planar_velocity(
	current: Vector2,
	wish: Vector2,
	dt: float,
	grounded: bool,
	accel_ground: float = ACCEL_GROUND,
	accel_turn: float = ACCEL_TURN,
	accel_stop: float = ACCEL_STOP,
	air_control: float = AIR_CONTROL,
	quiet_stance: bool = false
) -> Vector2:
	var has_wish := wish.length_squared() > 0.0001
	var accel := accel_ground if has_wish else accel_stop
	if has_wish and current.dot(wish) < 0.0:
		accel = accel_turn
	if quiet_stance and has_wish:
		accel = ACCEL_QUIET
	if not grounded:
		accel *= air_control
	return current.move_toward(wish, dt * accel)

static func stride_for_stance(stance: int) -> float:
	return STRIDE_LENGTHS[clampi(stance, 0, STRIDE_LENGTHS.size() - 1)]

static func aim_gain_scale(aim: float) -> float:
	return lerpf(1.0, AIM_SENS_SCALE, clampf(aim, 0.0, 1.0))

static func landing_dip(impact_vy: float) -> float:
	var down := maxf(0.0, -impact_vy)
	if down < LAND_MIN_SPEED:
		return 0.0
	return clampf(down * 0.0115, 0.02, 0.13)

static func landing_trauma(impact_vy: float) -> float:
	var down := maxf(0.0, -impact_vy)
	if down < LAND_MIN_SPEED:
		return 0.0
	return clampf(down * 0.024, 0.04, 0.20)
