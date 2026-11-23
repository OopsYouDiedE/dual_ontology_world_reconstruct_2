extends RefCounted
## Short deterministic Foley placeholders; the hum loops on a full period.
static func make(kind:String)->AudioStreamWAV:
	var wave:=AudioStreamWAV.new();wave.mix_rate=16000;wave.format=AudioStreamWAV.FORMAT_16_BITS
	var n:=8000 if kind=="hum" else 3200;var bytes:=PackedByteArray();bytes.resize(n*2);var rng:=RandomNumberGenerator.new();rng.seed=412
	for i in n:
		var t:=float(i)/16000.;var noise:=rng.randf_range(-1,1);var v:=0.
		match kind:
			"stone":v=(.6*noise+.4*sin(TAU*96*t))*exp(-42*t)
			"wood":v=(sin(TAU*155*t)+.3*noise)*exp(-34*t)
			"iron":v=(.5*sin(TAU*710*t)+.32*sin(TAU*1130*t)+.18*noise)*exp(-21*t)
			"hum":v=.3*sin(TAU*92*t)+.1*sin(TAU*184*t)
			"tick":v=sin(TAU*1190*t)*exp(-53*t)
			"cue":v=.6*sin(TAU*554*t)*exp(-18*t)
		bytes.encode_s16(2*i,int(clampf(v,-1.,1.)*20000))
	wave.data=bytes
	if kind=="hum":wave.loop_mode=AudioStreamWAV.LOOP_FORWARD;wave.loop_end=n
	return wave
