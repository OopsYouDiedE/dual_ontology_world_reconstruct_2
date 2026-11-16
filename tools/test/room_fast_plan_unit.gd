extends SceneTree
## Synthetic plan data only. Tests report semantics, not a real game run.
const Check := preload("res://scenes/components/testing/RoomFastCheck.gd")
var tests := 0
var failures := 0
func _initialize() -> void:
	print("SYNTHETIC PLAN FIXTURE: NOT GAME ACCEPTANCE")
	var start := Vector2(2, 3)
	var requested := Vector2(7, 1)
	var calls := [0]
	var fallback := func(_from: Vector2, _to: Vector2) -> Array:
		calls[0] += 1
		return [Vector2(4, 4)]
	var rejected := {"stand": start, "already_near": false, "approach_ok": false, "planned_path": []}
	check("rejected plan is empty", Check.production_plan_path(rejected, start, fallback).is_empty())
	check("rejected plan never calls fallback router", calls[0] == 0)
	check("rejected plan cannot turn fallback into target reached", not Check.navigation_target_claim(true, false))
	var impossible := {"stand": start, "already_near": true, "approach_ok": false, "planned_path": []}
	check("rejection wins over contradictory already-near", Check.production_plan_path(impossible, start, fallback).is_empty())
	var near := {"stand": start, "already_near": true, "approach_ok": true, "planned_path": []}
	check("valid already-near plan retains origin", Check.production_plan_path(near, start, fallback) == [start])
	var points := [Vector2(3, 3), Vector2(5, 2), requested]
	var kitchen := {"stand": requested, "already_near": false, "approach_ok": true, "planned_path": points}
	check("kitchen uses actual planned path", Check.production_plan_path(kitchen, start, fallback) == points)
	check("planned path does not call fallback router", calls[0] == 0)
	var other := {"stand": requested, "already_near": false}
	check("other room may use its production router", Check.production_plan_path(other, start, fallback) == [Vector2(4, 4)] and calls[0] == 1)
	check("accepted plan plus successful navigation is true", Check.navigation_target_claim(true, true))
	check("accepted plan plus failed navigation is false", not Check.navigation_target_claim(false, true))
	var targets := []
	for id in Check.REQUIRED_TARGETS.kitchen: targets.append({"id":id})
	check("complete kitchen target set accepted", Check.target_coverage("kitchen", targets).complete)
	check("empty target list fails closed", not Check.target_coverage("kitchen", []).complete)
	check("missing target fails closed", not Check.target_coverage("kitchen", targets.slice(0,6)).complete)
	var duplicated := targets.duplicate(true); duplicated.append({"id":"e_b_water"})
	check("duplicate target fails closed", not Check.target_coverage("kitchen", duplicated).complete)
	var unexpected := targets.duplicate(true); unexpected.append({"id":"not-a-target"})
	check("unexpected target fails closed", not Check.target_coverage("kitchen", unexpected).complete)
	var malformed := targets.duplicate(true); malformed.append({})
	check("malformed target fails closed", not Check.target_coverage("kitchen", malformed).complete)
	check("unsupported room cannot vacuously pass", not Check.target_coverage("other", []).complete)
	var bedroom := []
	for id in Check.REQUIRED_TARGETS.opening: bedroom.append({"id":id})
	check("complete bedroom target set accepted", Check.target_coverage("opening", bedroom).complete)
	check("required ray cannot pass when inapplicable", not Check.ray_claim({"pass":true,"applicable":false}, true))
	check("required ray passes only when applicable and hit", Check.ray_claim({"pass":true,"applicable":true}, true))
	check("blocked required ray fails", not Check.ray_claim({"pass":false,"applicable":true}, true))
	check("explicit non-evidence exit may be inapplicable", Check.ray_claim({"pass":true,"applicable":false}, false))
	check("missing ray result cannot pass", not Check.ray_claim({}, false))
	print("SYNTHETIC RESULT tests=", tests, " failures=", failures, " acceptance_eligible=false")
	quit(0 if failures == 0 else 1)
func check(name: String, condition: bool) -> void:
	tests += 1
	print(("PASS " if condition else "FAIL ") + name)
	if not condition: failures += 1
