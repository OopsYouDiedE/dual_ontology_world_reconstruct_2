extends SkeletonModifier3D
## 起床表演用的骨骼叠加层：在 AnimationPlayer 的躺姿（lie_idle）之上，
## 把上身从床上撑起来（sit），并让头颈左右张望、低头、歪头（head_yaw / head_pitch / head_roll）。
## 只改旋转，不改骨长；所有量为 0 时对原动画没有任何影响。

const ImportedCharacter := preload("res://scenes/components/characters/ImportedCharacter.gd")

## 0 = 平躺，1 = 上身撑到 sit_elevation 的仰角
var sit := 0.0
var sit_elevation := deg_to_rad(66.0)
var head_yaw := 0.0
var head_pitch := 0.0
var head_roll := 0.0

var _hips := -1
var _spine := -1
var _spine1 := -1
var _neck := -1
var _head := -1
var ready_ok := false


func setup(skeleton: Skeleton3D) -> bool:
	_hips = ImportedCharacter._find_mixamo_bone(skeleton, "Hips")
	_spine = ImportedCharacter._find_mixamo_bone(skeleton, "Spine")
	_spine1 = ImportedCharacter._find_mixamo_bone(skeleton, "Spine1")
	_neck = ImportedCharacter._find_mixamo_bone(skeleton, "Neck")
	_head = ImportedCharacter._find_mixamo_bone(skeleton, "Head")
	ready_ok = _hips >= 0 and _spine >= 0 and _neck >= 0 and _head >= 0
	return ready_ok


func _process_modification() -> void:
	if not ready_ok: return
	var sk := get_skeleton()
	if sk == null: return
	if sit > 0.001: _apply_sit(sk)
	if absf(head_yaw) + absf(head_pitch) + absf(head_roll) > 0.001: _apply_head(sk)


## 以脊柱根为支点，把躯干长轴朝「世界上方」转过去，等于在床上撑起上身。
func _apply_sit(sk: Skeleton3D) -> void:
	var spine := sk.get_bone_global_pose(_spine)
	var neck_origin := sk.get_bone_global_pose(_neck).origin
	var torso := (neck_origin - spine.origin).normalized()
	var up := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var axis := torso.cross(up)
	if axis.length() < 0.05: return
	axis = axis.normalized()
	var current := asin(clampf(torso.dot(up), -1.0, 1.0))
	var target := lerpf(current, maxf(current, sit_elevation), clampf(sit, 0.0, 1.0))
	var angle := target - current
	if absf(angle) < 0.0005: return
	var rot := Basis(axis, angle)
	sk.set_bone_global_pose(_spine, Transform3D(rot * spine.basis, spine.origin))


func _apply_head(sk: Skeleton3D) -> void:
	_rotate_bone(sk, _neck, 0.4)
	_rotate_bone(sk, _head, 0.6)


func _rotate_bone(sk: Skeleton3D, bone: int, share: float) -> void:
	var pose := sk.get_bone_global_pose(bone)
	var b := pose.basis
	var rot := Basis(b.y.normalized(), head_yaw * share) \
		* Basis(b.x.normalized(), head_pitch * share) \
		* Basis(b.z.normalized(), head_roll * share)
	sk.set_bone_global_pose(bone, Transform3D(rot * b, pose.origin))
