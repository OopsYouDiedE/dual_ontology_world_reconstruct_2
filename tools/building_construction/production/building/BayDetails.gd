extends RefCounted
## Bay-local detailing, in the same metre coordinate system as shell and cutbacks.
static func quad(s,k,m,a,b,c,d,mask:=0)->void:
	s.facet(k,m,a,b,c,mask);s.facet(k,m,a,c,d,mask)
static func sweep(s,k,mat,path:PackedVector3Array,section:PackedVector2Array)->void:
	if path.size()<2:return
	var rings=[];var last_side=Vector3.ZERO
	for i in path.size():
		var ta=(path[i]-path[maxi(i-1,0)]).normalized();var tb=(path[mini(i+1,path.size()-1)]-path[i]).normalized();var tangent=(ta+tb).normalized()
		var side=tangent.cross(Vector3.UP).normalized();if side.length_squared()<.01:side=last_side if last_side!=Vector3.ZERO else Vector3.RIGHT
		if last_side.dot(side)<0:side=-side
		var up=side.cross(tangent).normalized();var miter=1. if ta==Vector3.ZERO or tb==Vector3.ZERO else 1./maxf(.5,tangent.dot(ta));var ring=[]
		for uv in section:ring.append(path[i]+side*uv.x*miter+up*uv.y)
		rings.append(ring);last_side=side
		if i>0:
			for j in section.size():
				var jj=(j+1)%section.size();quad(s,k,mat,rings[i-1][j],ring[j],ring[jj],rings[i-1][jj])
	for end in [0,rings.size()-1]:
		var ring=rings[end];for j in range(1,ring.size()-1):s.facet(k,mat,ring[0],ring[j if end==0 else j+1],ring[j+1 if end==0 else j])
static func dress(s,k:String,b:Vector3,t:int,hole:String,up:String)->void:
	var bay:float=s.BAY;var center=b+Vector3(bay/2,0,bay/2)
	if hole=="" and up=="":
		if t in [0,3]:
			# Insets form a coffer aligned to the column bay. Keep the stair envelope empty.
			for d in [-1,1]:
				s.box(k+"/cofferX",center+Vector3(0,2.98,d*1.77),Vector3(3.66,.13,.12),"cream",0)
				s.box(k+"/cofferZ",center+Vector3(d*1.77,2.98,0),Vector3(.12,.13,3.44),"cream",0)
		if t==5:
			for i in 10:s.box(k+"/grate",center+Vector3(.5,.023,(i-4.5)*.12),Vector3(.62,.036,.045),"grout",0)
		if t==0 or t==2:
			for x in 4:
				for z in 4:
					var p=b+Vector3((x+.5)*bay/4,.006,(z+.5)*bay/4);var h=bay/8-.008;var a=Vector3(h,0,0);var v=Vector3(0,0,h);quad(s,k,"tile_light" if (x+z)%2 else ("stone" if t==0 else "green"),p-a-v,p+a-v,p+a+v,p-a+v)
static func arch(s,k:String,center:Vector3,along:Vector3,n:Vector3,r:float)->void:
	for i in 11:
		var a=i*PI/11.+.006;var b=(i+1)*PI/11.-.006;var rings=[]
		for depth in [.13,.21]:
			var q=[];for uv in [[a,r],[b,r],[b,r+.12],[a,r+.12]]:q.append(center+(along*cos(uv[0])+Vector3.UP*sin(uv[0]))*uv[1]-n*depth)
			rings.append(q)
		var f=rings[1];var back=rings[0];quad(s,k,"stone",f[3],f[2],f[1],f[0]);quad(s,k,"stone",back[0],back[1],back[2],back[3]);for j in 4:quad(s,k,"stone_dark",f[j],back[j],back[(j+1)%4],f[(j+1)%4])
static func wall_trim(s,k:String,id:String,center:Vector3,along:Vector3,n:Vector3,w:float,t:int)->void:
	var profile=PackedVector2Array([Vector2(-.04,-.06),Vector2(.04,-.06),Vector2(.04,.025),Vector2(.015,.06),Vector2(-.04,.06)])
	for side in [-1,1]:
		var lo=w/2+.07;var hi=s.BAY/2-.17;var net=hi-lo;var count=maxi(1,roundi(net/.62));var a=center+along*side*lo-n*.14;var b=center+along*side*hi-n*.14
		for y in [.12,.89]:sweep(s,k,"wood",PackedVector3Array([a+Vector3.UP*y,b+Vector3.UP*y]),profile)
		for j in count:
			var p=a.lerp(b,(j+.5)/count)+Vector3.UP*.50;s.box(id+"/panel",p,Vector3(net/count-.045,.63,.035),"wood_light" if t!=5 else "stone_dark",0,-atan2(along.z,along.x))
static func dome(s,k:String,pts:Array)->void:
	# Reuse the actual heights of the eight roof edge stations; the surrounding hip stays watertight.
	var c:Vector3=pts[0];var spring=c.y+.12;var rings=[];var n=32;var radius=1.62
	for j in 8:
		var row=[];var phi=j*PI/16.
		for i in n:
			var angle=TAU*i/n;row.append(Vector3(c.x+radius*cos(phi)*cos(angle),spring+1.35*sin(phi),c.z+radius*cos(phi)*sin(angle)))
		rings.append(row)
	var top=Vector3(c.x,spring+1.35,c.z)
	for i in n:
		var ix=(i+1)%n;var a:Vector3=rings[0][i];var b:Vector3=rings[0][ix];var j0=(i/4+3)%8;var j1=(j0+1)%8;var e:Vector3=pts[j0+1].lerp(pts[j1+1],(i%4)/4.);var f:Vector3=pts[j0+1].lerp(pts[j1+1],(i%4+1)/4.)
		quad(s,k,"book_blue",e,f,b,a,3)
		for j in 7:
			var p=[rings[j][i],rings[j][ix],rings[j+1][ix],rings[j+1][i]]
			for ids in [[0,1,2],[0,2,3]]:
				var ns=[];for v in ids:ns.append(((p[v]-Vector3(c.x,spring,c.z))/Vector3(radius*radius,1.35*1.35,radius*radius)).normalized())
				s.facet(k,"book_blue",p[ids[0]],p[ids[1]],p[ids[2]],3,ns)
		s.facet(k,"book_blue",rings[7][i],rings[7][ix],top,3)
