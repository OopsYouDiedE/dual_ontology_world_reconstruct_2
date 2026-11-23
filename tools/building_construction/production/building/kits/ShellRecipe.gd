extends RefCounted
func emit(s,q):
	var id=q.edge;var center=q.p;var boundary=q.boundary;var opened=q.open;var door=q.door;var t=q.type;var other=q.other;var shared=other>=0
	var n=q.n;var along=q.along;var yaw=q.yaw;var d=q.d;var thick=q.thick;var w=q.w;var low=q.low;var high=q.high
	var spans=[[-s.BAY/2,-w/2,0,boundary],[w/2,s.BAY/2,0,boundary],[-w/2,w/2,high,boundary]]
	if not opened:spans=[[-s.BAY/2,s.BAY/2,0,boundary]]
	var niche=opened and not door and t==5 and d==Vector2i.RIGHT
	if niche:
		var depth=.34;var back=.075
		if depth+back>thick:
			niche=s.repair(id,"valve niche deeper than wall → project exterior backing pier")
		if niche:
			# Carve a local rectangle in the positive jamb, retain material around its perimeter.
			var jamb=spans[1];spans.remove_at(1);var middle=(jamb[0]+jamb[1])*.5;var left=middle-.31;var right=middle+.31
			spans.append_array([[jamb[0],left,0,boundary],[right,jamb[1],0,boundary],[left,right,0,1.08],[left,right,1.85,boundary]])
			var origin=center+along*middle-n*thick/2;s.box(id+"/niche-back",origin+n*(depth+back*.5)+Vector3.UP*1.465,Vector3(.62+2*back,.77+2*back,back),"stone_dark",3,yaw)
			for h in [1.08,1.85]:s.box(id+"/niche-return",origin+n*depth/2+Vector3.UP*h,Vector3(.62,back,depth),"stone",3,yaw)
			for j in [-1,1]:s.box(id+"/niche-side",origin+n*depth/2+along*j*.31+Vector3.UP*1.465,Vector3(back,.77,depth),"stone",3,yaw)
	if opened and low>0:spans.append([-w/2,w/2,0,low])
	for i in spans.size():
		var r=spans[i];var p=center+along*((r[0]+r[1])*.5)+Vector3.UP*((r[2]+r[3])*.5);var sz=Vector3(r[1]-r[0],r[3]-r[2],thick)
		s.box(id+"/wall%d"%i,p,sz,"stone",3,yaw)
		for side in [-1,1]:
			var mat=s.FINISH[t] if side<0 else (s.FINISH[other] if shared else "stone_dark")
			s.box(id+"/finish",p+n*side*(thick*.5+.006),Vector3(sz.x,sz.y,.012),mat,0,yaw)
