extends RefCounted
func emit(s,q):
	var k=q.owner;var b=q.p;var kind=q.core
	if kind=="service":
		s.box(k+"/riser",b+Vector3(.94,s.heights[s.address(k).z]/2,.94),Vector3(.34,s.heights[s.address(k).z],.34),"gold");s.socket("valve/"+k,"valve",b+Vector3(.94,1.2,1.2),{"network":"riser/%d/%d"%[s.address(k).x,s.address(k).y]});return
	var rise:float=s.heights[s.address(k).z];var start:Vector3;var end:Vector3;var rails=[PackedVector3Array(),PackedVector3Array()]
	if kind=="spiral":
		var center=b+Vector3(2.1,0,2.1);var delta=TAU/14.;var offset=-PI/2-17*delta
		for i in 18:
			var a=offset+i*delta;var p=center+Vector3(cos(a),0,sin(a))*.88+Vector3.UP*((i+1)*rise/18.-.075)
			s.box(k+"/tread%d"%i,p,Vector3(1.45,.15,.69),"wood_light",3,-a)
			var edge=p+Vector3(cos(a)*.69,1.,sin(a)*.69);rails[0].append(edge)
			if i%2==0:s.box(k+"/baluster%d"%i,edge-Vector3.UP*.46,Vector3(.04,.92,.04),"gold",1)
			if i==0:start=p+Vector3.UP*.1
		end=center+Vector3(0,rise,-1.62);s.box(k+"/landing",end-Vector3.UP*.075,Vector3(.9,.15,.56),"wood")
	else:
		var turn_z=1.08;var entry_z=3.84;var half=rise*.5
		for flight in 2:
			var x=.99 if flight==0 else 2.29
			var foot=b+Vector3(x,half*flight,entry_z if flight==0 else turn_z)
			var head=b+Vector3(x,half*(flight+1),turn_z if flight==0 else entry_z)
			var side=Vector3.RIGHT*.55*(1 if flight==0 else -1)
			s.facet(k,"walk_proxy",foot-side,head+side,foot+side,s.MOVE)
			s.facet(k,"walk_proxy",foot-side,head-side,head+side,s.MOVE)
			var detail=preload("../BayDetails.gd")
			for dx in [-.50,.50]:
				var offset=Vector3.RIGHT*dx
				detail.stair_guard(s,k,foot+offset,head+offset)
				var underside=offset-Vector3.UP*.10
				detail.sweep(s,k,"wood_dark",PackedVector3Array([foot+underside,head+underside]),PackedVector2Array([Vector2(-.05,-.09),Vector2(-.05,.09),Vector2(.05,.09),Vector2(.05,-.09)]),3)
			for i in 9:
				var pos=foot.lerp(head,(i+.5)/9.)+Vector3.UP*(half/18.-.08)
				s.box(k+"/tread%d"%(flight*9+i),pos,Vector3(1.1,.16,(entry_z-turn_z)/9.),"wood_light",s.SIGHT)
		start=b+Vector3(.99,0,entry_z);end=b+Vector3(2.29,rise,entry_z)
		s.box(k+"/landing",b+Vector3(1.64,half-.08,(.18+turn_z)*.5),Vector3(2.4,.16,turn_z-.18),"wood")
		var perimeter=[Vector3(.49,half,turn_z),Vector3(.49,half,.22),Vector3(2.79,half,.22),Vector3(2.79,half,turn_z)]
		for i in 3:preload("../BayDetails.gd").stair_guard(s,k,b+perimeter[i],b+perimeter[i+1])
		for z in [.30,turn_z-.06]:
			s.box(k+"/landing-joist",b+Vector3(1.64,half-.25,z),Vector3(2.4,.18,.14),"wood_dark")
			for x in [.52,2.76]:
				s.box(k+"/landing-post",b+Vector3(x,(half-.34)*.5,z),Vector3(.14,half-.34,.14),"wood")
	for path in rails:
		preload("../BayDetails.gd").sweep(s,k,"wood_dark",path,PackedVector2Array([Vector2(-.035,-.03),Vector2(-.035,.03),Vector2(.035,.03),Vector2(.035,-.03)]))
	s.links.append([k,start,end]);s.socket("stairs/"+k,"link",start,{"end":end})
