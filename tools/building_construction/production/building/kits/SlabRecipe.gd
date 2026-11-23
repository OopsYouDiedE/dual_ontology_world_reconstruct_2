extends RefCounted
func emit(s,q):
	var k=q.owner;var b=q.p;var hole=q.hole
	var lo=Vector2.ZERO;var hi=Vector2.ZERO
	if hole=="trench":lo=Vector2(2.44,1.24);hi=Vector2(3.0,2.96)
	elif hole=="service":lo=Vector2(.6,.6);hi=Vector2(1.28,1.28)
	elif hole=="stair":lo=Vector2(.43,.18);hi=Vector2(2.85,3.84)
	elif hole=="spiral":lo=Vector2(.5,.5);hi=Vector2(3.7,3.7)
	var rects=[[0,0,s.BAY,s.BAY]] if hole=="" else [[0,0,lo.x,s.BAY],[hi.x,0,s.BAY,s.BAY],[lo.x,0,hi.x,lo.y],[lo.x,hi.y,hi.x,s.BAY]]
	for i in rects.size():
		var r=rects[i];s.box(k+"/slab%d"%i,b+Vector3((r[0]+r[2])/2,-.09,(r[1]+r[3])/2),Vector3(r[2]-r[0],.18,r[3]-r[1]),"stone")
	if hole not in ["","trench"]:
		for rx in [lo.x,hi.x]:s.box(k+"/guard",b+Vector3(rx,.53,(lo.y+hi.y)/2),Vector3(.055,1.06,hi.y-lo.y),"gold",1)
		if hole=="stair":
			s.box(k+"/guard-low-end",b+Vector3(1.055,.53,hi.y),Vector3(1.25,1.06,.055),"gold",1)
		var closed_z=lo.y if hole=="stair" else hi.y
		s.box(k+"/guard",b+Vector3((lo.x+hi.x)/2,.53,closed_z),Vector3(hi.x-lo.x,1.06,.055),"gold",1)
