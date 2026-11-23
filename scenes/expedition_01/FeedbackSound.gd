extends RefCounted
## Short deterministic Foley placeholders; the hum loops on a full period.
static func make(kind:String)->AudioStreamWAV:
	var wave:=AudioStreamWAV.new();wave.mix_rate=16000;wave.format=AudioStreamWAV.FORMAT_16_BITS
	var n:=19200 if kind in ["slam","bell","scream","breath","alarm"] else 8000 if kind=="hum" else 3200;var bytes:=PackedByteArray();bytes.resize(n*2);var rng:=RandomNumberGenerator.new();rng.seed=412
	for i in n:
		var t:=float(i)/16000.;var noise:=rng.randf_range(-1,1);var v:=0.
		match kind:
			"stone":v=(.15*noise+.65*sin(TAU*96*t))*exp(-42*t)
			"wood":v=(sin(TAU*155*t)+.3*noise)*exp(-34*t)
			"iron":v=(.42*sin(TAU*390*t)+.22*sin(TAU*640*t)+.10*noise)*exp(-21*t)
			"hum":v=.3*sin(TAU*92*t)+.1*sin(TAU*184*t)
			"tick":v=sin(TAU*1190*t)*exp(-53*t)
			"cue":v=.6*sin(TAU*554*t)*exp(-18*t)
			"slam":v=(.65*sin(TAU*64*t)+.35*noise)*exp(-7*t)
			"bell":v=(.65*sin(TAU*88*t)+.2*sin(TAU*220*t))*exp(-2.3*t)
			"scream":v=.65*sin(TAU*(360*t+135*t*t)+1.3*sin(TAU*63*t))*sin(PI*t/1.2)
			"alarm":v=.55*sin(TAU*(330*t+72*t*t))*sin(PI*t/1.2)
			"breath":v=(.30*sin(TAU*67*t)+.08*noise)*sin(PI*t/1.2)
		bytes.encode_s16(2*i,int(clampf(v*minf(1.,i/90.),-1.,1.)*20000))
	wave.data=bytes
	if kind=="hum":wave.loop_mode=AudioStreamWAV.LOOP_FORWARD;wave.loop_end=n
	return wave
