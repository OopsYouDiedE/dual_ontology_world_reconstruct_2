extends RefCounted
## Bay-local detailing, in the same metre coordinate system as shell and cutbacks.
static func quad(s,k,m,a,b,c,d,mask:=0)->void:
	s.facet(k,m,a,b,c,mask);s.facet(k,m,a,c,d,mask)
static func sweep(s,k,mat,path:PackedVector3Array,section:PackedVector2Array,mask:=0)->void:
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
				var jj=(j+1)%section.size();quad(s,k,mat,rings[i-1][j],ring[j],ring[jj],rings[i-1][jj],mask)
	for end in [0,rings.size()-1]:
		var ring=rings[end];for j in range(1,ring.size()-1):s.facet(k,mat,ring[0],ring[j if end==0 else j+1],ring[j+1 if end==0 else j],mask)
static func dress(s,k:String,b:Vector3,t:int,hole:String,up:String)->void:
	var bay:float=s.BAY;var center=b+Vector3(bay/2,0,bay/2)
	if hole=="" and up=="":
		if t==5:pump_tray(s,k,center)
		if t==0 or t==2:
			for x in 4:
				for z in 4:
					var p=b+Vector3((x+.5)*bay/4,.006,(z+.5)*bay/4);var h=bay/8-.008;var a=Vector3(h,0,0);var v=Vector3(0,0,h);quad(s,k,"tile_light" if (x+z)%2 else ("stone" if t==0 else "green"),p-a-v,p+a-v,p+a+v,p-a+v)
static func frame(s,k,c,tier:Array)->void:
	var r:float=tier[0];var w:float=tier[2];var h:float=tier[3]
	for d in [-1,1]:
		s.box(k+"/coffer",c+Vector3(0,tier[1],r*d),Vector3(2*r+w,h,w),tier[4],0)
		s.box(k+"/coffer",c+Vector3(r*d,tier[1],0),Vector3(w,h,2*r-w),tier[4],0)

static func pump_tray(s,k,c)->void:
	# Four slab bands frame this recessed service channel; flush bars bridge it.
	var o:Vector3=c+Vector3(.62,-.145,0)
	s.box(k+"/channel",o+Vector3.UP*.012,Vector3(.56,.024,1.72),"grout",3)
	var pipe=PackedVector2Array()
	for i in 8:pipe.append(Vector2(cos(TAU*i/8),sin(TAU*i/8))*.038)
	for side in [-1,1]:
		var run=o+Vector3(side*.13,.066,0)
		sweep(s,k,"gold",PackedVector3Array([run+Vector3.FORWARD*.83,run+Vector3.BACK*.83]),pipe)
		s.box(k+"/channel-rim",o+Vector3(side*.27,.065,0),Vector3(.035,.13,1.72),"stone_dark",0)
	for z in [-.58,.58]:
		sweep(s,k,"gold",PackedVector3Array([o+Vector3(-.13,.066,z),o+Vector3(.13,.066,z)]),pipe)
	for i in 9:s.box(k+"/grate",o+Vector3(0,.139,(i-4)*.20),Vector3(.56,.024,.045),"stone_dark",1)

static func arch(s,k:String,center:Vector3,along:Vector3,n:Vector3,r:float,rise_ratio:=1.0)->void:
	for i in 11:
		var a=i*PI/11.+.006;var b=(i+1)*PI/11.-.006;var rings=[]
		for depth in [.13,.21]:
			var q=[];for uv in [[a,r],[b,r],[b,r+.12],[a,r+.12]]:q.append(center+(along*cos(uv[0])+Vector3.UP*sin(uv[0])*rise_ratio)*uv[1]-n*depth)
			rings.append(q)
		var f=rings[1];var back=rings[0];quad(s,k,"stone",f[3],f[2],f[1],f[0]);quad(s,k,"stone",back[0],back[1],back[2],back[3]);for j in 4:quad(s,k,"stone_dark",f[j],back[j],back[(j+1)%4],f[(j+1)%4])
static func wall_trim(s,k:String,id:String,center:Vector3,along:Vector3,n:Vector3,w:float,thick:float,door:bool)->void:
	var yaw=-atan2(along.z,along.x)
	center-=n*(thick*.5-.11)
	var hi:float=s.BAY*.5
	for side in [-1,1]:
		var lo=w*.5+.08 if door else 0.;var span=hi-lo
		if span<.16:continue
		var mid=center+along*side*(lo+span*.5)
		# All layers project inward from the finished wall face (depth .122).
		for rail in [[.10,.16,.17],[.82,.11,.16],[.91,.06,.19]]:
			s.box(id+"/rail",mid-n*(.122+rail[2]*.25)+Vector3.UP*rail[0],Vector3(span,rail[1],rail[2]*.5),"wood_dark",0,yaw)
		var count=maxi(1,roundi(span/.54));var pitch=span/count
		for j in count:
			var p=center+along*side*(lo+pitch*(j+.5))+Vector3.UP*.47
			s.box(id+"/panel-field",p-n*.143,Vector3(pitch,.64,.04),"wood_dark",0,yaw)
			s.box(id+"/panel-frame",p-n*.17,Vector3(pitch-.04,.56,.024),"wood_light",0,yaw)
			s.box(id+"/panel-inset",p-n*.186,Vector3(pitch-.10,.46,.014),"wood",0,yaw)
# Call once per solved beam; endpoints already include column overrides.
static func beam_corbels(s,id:String,a:Vector3,b:Vector3)->void:
	var axis=a.direction_to(b);var yaw=-atan2(axis.z,axis.x)
	for i in 2:
		var post=a if i==0 else b
		var inward=axis if i==0 else -axis
		for tier in [[.30,2.79,.20],[.41,2.925,.07],[.52,2.98,.04]]:
			var length:float=tier[0]-.08
			var p=post+inward*(.08+length*.5)+Vector3.UP*tier[1]
			s.box(id+"/corbel%d"%i,p,Vector3(length,tier[2],.30),"cream" if tier[1]>2.9 else "stone",0,yaw)
# A rail follows the actual flight pitch; end posts terminate on the landing or tread.
static func stair_guard(s,k:String,a:Vector3,b:Vector3)->void:
	var lift=Vector3.UP*.94
	var count=maxi(1,ceili(Vector2(b.x-a.x,b.z-a.z).length()/.40))
	for i in range(count+1):
		var foot=a.lerp(b,float(i)/count)
		s.box(k+"/guard-post",foot+lift*.5,Vector3(.032,.94,.032),"gold",1)
	for h in [.45,.94]:
		var path=PackedVector3Array([a+Vector3.UP*h,b+Vector3.UP*h]);var r=.035 if h>.5 else .018
		sweep(s,k,"wood_dark",path,PackedVector2Array([Vector2(-r,-r),Vector2(-r,r),Vector2(r,r),Vector2(r,-r)]),1)
static func dome(s,k:String,pts:Array)->void:
	# Reuse the actual heights of the eight roof edge stations; the surrounding hip stays watertight.
	var c:Vector3=pts[0];var spring=c.y+.52;var rings=[];var n=32;var radius=1.62
	for j in 8:
		var row=[];var phi=j*PI/16.
		for i in n:
			var angle=TAU*i/n;row.append(Vector3(c.x+radius*cos(phi)*cos(angle),spring+1.35*sin(phi),c.z+radius*cos(phi)*sin(angle)))
		rings.append(row)
	var top=Vector3(c.x,spring+1.35,c.z)
	for i in n:
		var ix=(i+1)%n;var a:Vector3=rings[0][i];var b:Vector3=rings[0][ix];var j0=(i/4+3)%8;var j1=(j0+1)%8;var e:Vector3=pts[j0+1].lerp(pts[j1+1],(i%4)/4.);var f:Vector3=pts[j0+1].lerp(pts[j1+1],(i%4+1)/4.)
		var foot_a:Vector3=a-Vector3.UP*.4;var foot_b:Vector3=b-Vector3.UP*.4
		quad(s,k,"book_blue",e,f,foot_b,foot_a,3);quad(s,k,"stone",foot_a,foot_b,b,a,3)
		for j in 7:
			var p=[rings[j][i],rings[j][ix],rings[j+1][ix],rings[j+1][i]]
			for ids in [[0,1,2],[0,2,3]]:
				var ns=[];for v in ids:ns.append(((p[v]-Vector3(c.x,spring,c.z))/Vector3(radius*radius,1.35*1.35,radius*radius)).normalized())
				s.facet(k,"book_blue",p[ids[0]],p[ids[1]],p[ids[2]],3,ns)
		s.facet(k,"book_blue",rings[7][i],rings[7][ix],top,3)

static func _circle_section(radius:float,sides:=8)->PackedVector2Array:
	var sec=PackedVector2Array()
	for i in sides:
		var a=TAU*float(i)/float(sides)
		sec.append(Vector2(cos(a)*radius,sin(a)*radius))
	return sec

## French Gothic pointed rib (ported from assembly.py FG | Pointed rib).
static func pointed_rib(s,k:String,a:Vector3,b:Vector3,rise:float,radius:=.10,mat:="cream",segs:=10)->void:
	var mid=(a+b)*.5+Vector3.UP*rise
	var sec=_circle_section(radius,8)
	for endpoint in [a,b]:
		var ctrl=endpoint+Vector3.UP*(rise*.64)
		var path=PackedVector3Array()
		for i in range(segs+1):
			var t=float(i)/float(segs);var u=1.-t
			path.append(endpoint*(u*u)+ctrl*(2.*u*t)+mid*(t*t))
		sweep(s,k,mat,path,sec,0)

## French Gothic quadripartite groin vault web + diagonal ribs (ported from full_structure.py FG2 | Vault web patch).
static func gothic_vault_web(s,k:String,spring_center:Vector3,half_x:float,half_z:float,rise:float,res:=9)->void:
	var n=clampi(res,5,17)
	var top=[];var bot=[]
	for iz in n:
		var nz=-1.+2.*float(iz)/float(n-1)
		for ix in n:
			var nx=-1.+2.*float(ix)/float(n-1)
			var u=minf(absf(nx),absf(nz));var t=sqrt(maxf(0.,1.-u))
			var dy=.05+rise*t*(1.28-.28*t)
			var pt=spring_center+Vector3(nx*half_x,dy,nz*half_z)
			top.append(pt);bot.append(pt-Vector3.UP*.075)
	for iz in n-1:
		for ix in n-1:
			var i0=iz*n+ix;var i1=i0+1;var i2=i0+n+1;var i3=i0+n
			quad(s,k,"stone",top[i0],top[i1],top[i2],top[i3],0)
			quad(s,k,"cream",bot[i3],bot[i2],bot[i1],bot[i0],0)
	var c0=spring_center+Vector3(-half_x,0,-half_z)
	var c1=spring_center+Vector3(half_x,0,-half_z)
	var c2=spring_center+Vector3(half_x,0,half_z)
	var c3=spring_center+Vector3(-half_x,0,half_z)
	pointed_rib(s,k,c0,c2,rise,.085,"cream",10)
	pointed_rib(s,k,c1,c3,rise,.085,"cream",10)
	s.box(k+"/vault-boss",spring_center+Vector3.UP*(rise-.02),Vector3(.30,.14,.30),"gold",0)

## French Gothic lower blind arcade + paired engaged wall shafts (ported from wall_lining.py).
static func gothic_blind_arcade(s,k:String,id:String,center:Vector3,along:Vector3,n:Vector3,w:float,thick:float,door:bool,height:float)->void:
	var yaw=-atan2(along.z,along.x)
	var face_base=center-n*(thick*.5+.025)
	var hi:float=s.BAY*.5
	var sec=_circle_section(.036,6)
	for side in [-1,1]:
		var lo=w*.5+.08 if door else 0.;var span=hi-lo
		if span<.25:continue
		var mid=face_base+along*side*(lo+span*.5)
		s.box(id+"/dado",mid+Vector3.UP*.55,Vector3(span,1.10,.05),"stone",0,yaw)
		s.box(id+"/sill-mould",mid+Vector3.UP*1.08-n*.04,Vector3(span,.11,.10),"cream",0,yaw)
		var count=maxi(1,roundi(span/.72));var pitch=span/count;var hw=pitch*.40
		for j in count:
			var ac=face_base+along*side*(lo+pitch*(j+.5))-n*.05
			var path=PackedVector3Array([ac-along*hw+Vector3.UP*.18,ac-along*hw+Vector3.UP*.64])
			for st in 7:
				var tt=-1.+2.*float(st)/6.
				path.append(ac+along*(tt*hw)+Vector3.UP*(.64+.28*pow(maxf(0.,1.-absf(tt)),.7)))
			path.append(ac+along*hw+Vector3.UP*.18)
			sweep(s,k,"cream",path,sec,0)
	for side in [-1,1]:
		var sx=face_base+along*(side*(hi-.16))-n*.06
		s.box(id+"/shaft",sx+Vector3.UP*(height*.5),Vector3(.11,height-.28,.11),"cream",0,yaw)
		s.box(id+"/shaft-cap",sx+Vector3.UP*(height-.24),Vector3(.26,.12,.22),"cream",0,yaw)

## French Gothic paired pointed lancet window (ported from wall_lining.py).
static func gothic_lancet_window(s,k:String,id:String,p:Vector3,along:Vector3,n:Vector3,w:float,low:float,high:float,thick:float,yaw:float)->void:
	var h:float=high-low;var mid_y=(low+high)*.5
	s.box(id+"/glass",p+Vector3.UP*mid_y,Vector3(w,h,.032),"glass",1,yaw)
	s.box(id+"/sill",p+Vector3.UP*low,Vector3(w+.14,.09,thick+.14),"cream",3,yaw)
	s.box(id+"/center-mullion",p+Vector3.UP*mid_y,Vector3(.09,h,.11),"stone",1,yaw)
	var spring=lerpf(low,high,.56);var peak=high-.05;var lhw=w*.22;var denom=sqrt(1.-pow(.35/1.35,2.))
	var sec=_circle_section(.034,6)
	for side in [-1,1]:
		var cx=p+along*(side*w*.25)-n*(thick*.5+.02)
		var path=PackedVector3Array([cx-along*lhw+Vector3.UP*low])
		for i in 11:
			var lx=-lhw+2.*lhw*float(i)/10.
			var u=(absf(lx)/lhw+.35)/1.35
			var ly=spring+(peak-spring)*sqrt(maxf(0.,1.-u*u))/denom
			path.append(cx+along*lx+Vector3.UP*ly)
		path.append(cx+along*lhw+Vector3.UP*low)
		sweep(s,k,"cream",path,sec,0)
		for frac in [.35,.68]:
			s.box(id+"/lead",p+along*(side*w*.25)+Vector3.UP*lerpf(low,spring,frac),Vector3(lhw*2.,.025,.05),"stone_dark",0,yaw)

## French Gothic 12-spoke branching rose window (ported from wall_lining.py).
static func gothic_rose_window(s,k:String,id:String,p:Vector3,along:Vector3,n:Vector3,w:float,low:float,high:float,thick:float,yaw:float)->void:
	var h:float=high-low;var mid=p+Vector3.UP*((low+high)*.5);var r=minf(w,h)*.44
	s.box(id+"/glass",mid,Vector3(w,h,.032),"glass",1,yaw)
	s.box(id+"/sill",p+Vector3.UP*low,Vector3(w+.14,.09,thick+.14),"cream",3,yaw)
	var face=mid-n*(thick*.5+.025);var ring_sec=_circle_section(.024,6);var spoke_sec=_circle_section(.015,6)
	for rad in [r,r*.20]:
		var rpath=PackedVector3Array()
		for i in 25:
			var a=TAU*float(i)/24.
			rpath.append(face+along*(cos(a)*rad)+Vector3.UP*(sin(a)*rad))
		sweep(s,k,"cream",rpath,ring_sec,0)
	for sp in 12:
		var a=(float(sp)+.5)*TAU/12.
		var p0=face+along*(cos(a)*r*.20)+Vector3.UP*(sin(a)*r*.20)
		var p1=face+along*(cos(a)*r)+Vector3.UP*(sin(a)*r)
		sweep(s,k,"cream",PackedVector3Array([p0,p1]),spoke_sec,0)
