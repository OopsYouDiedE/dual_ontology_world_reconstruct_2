extends SceneTree
## A continuous capsule traversal. Navigation targets are floor coordinates, never teleports.
var level
var failures:=0
func _initialize()->void:run.call_deferred()
func go(x:float,z:float,limit:=2000)->bool:
	var target:=Vector3(x,0,z);Input.action_press("move_up")
	for i in limit:
		var p:Vector3=level.walker.position;var d:Vector3=target-p;d.y=0
		if d.length()<.12:Input.action_release("move_up");return true
		level.walker.rotation.y=atan2(-d.x,-d.z);await physics_frame
	for k in level.walker.get_slide_collision_count():print(level.walker.get_slide_collision(k).get_collider().get_path(),level.walker.get_slide_collision(k).get_normal())
	Input.action_release("move_up");push_error("Blocked at %s approaching %s"%[level.walker.position,target]);failures+=1;return false
func run()->void:
	level=preload("Expedition.tscn").instantiate();root.add_child(level);await physics_frame
	for point in [[31,0],[31,4.9],[26.7,4.9],[25.7,5.5],[20.95,5.5],[20.95,9.8],[23.85,9.8],[23.85,12],[25.5,14.1],[28.3,14.1],[34,14.1],[38.9,14.1],[38.9,10],[36.6,8.5]]:
		if not await go(point[0],point[1]):quit(1);return
		if absf(point[0]-34)<.01:level.use()
	level.use();if not (level.learned and level.released and level.equipped):push_error("Archive state incomplete");quit(1);return
	for point in [[39,10.1],[48.8,10.1]]:
		if not await go(point[0],point[1]):quit(1);return
	level.order();for i in 950:await physics_frame
	if not level.holding:push_error("Hale did not reach north window");quit(1);return
	level.use();if not await go(70.95,10.1):quit(1);return
	level.use();if not level.collected:quit(1);return
	if not await go(70.95,11.45):quit(1);return
	if not await go(73.35,11.45):quit(1);return
	if not await go(73.35,9.12):quit(1);return
	for i in range(1,42):
		var a:=PI*.5+TAU*i/41.
		if not await go(73.35+1.02*cos(a),8.1+1.02*sin(a),250):quit(1);return
	if level.walker.position.y<4.5:push_error("Missed upper landing: %s"%level.walker.position);quit(1);return
	if not await go(73.35,12.1):quit(1);return
	level.use();if level.walker.position.x>40:push_error("Return leaf out of reach");quit(1);return
	for point in [[38.7,7.2],[38.7,0],[34,0],[1.5,0]]:
		if not await go(point[0],point[1]):quit(1);return
	var completed:=[false];level.returned.connect(func():completed[0]=true);level.use()
	if not completed[0]:push_error("Exit signal missing");quit(1);return
	print("PASS: A1 → B1 → B2 → B3 → B4 → B5 → C1 → C2 → C4 → upper return → B5 → A1 exit; Hale watches through glazing.");quit(0)
