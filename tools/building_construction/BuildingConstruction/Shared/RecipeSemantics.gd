@tool
extends RefCounted

# Small native helpers for the source recipes' sequence operations.
# No Python runtime or generated model is loaded by the recipes.
static func truth(value) -> bool:
	if value == null: return false
	if value is Array or value is Dictionary or value is String: return not value.is_empty()
	return bool(value)

static func either(a, b): return a if truth(a) else b
static func both(a, b): return b if truth(a) else a
static func either_lazy(a, b): return a if truth(a) else b.call()
static func both_lazy(a, b): return b.call() if truth(a) else a
static func add(a, b): return a + b
static func sub(a, b): return a - b
static func mul(a, b):
	if a is Array and (b is int or b is float):
		var result = []
		for _i in range(int(b)): result.append_array(a.duplicate(true))
		return result
	if b is Array: return mul(b, a)
	return a * b
static func div(a, b): return a / float(b)
static func floor_div(a, b): return floori(a / float(b))
static func mod(a, b):
	if a is String: return a % b
	if a is int and b is int: return posmod(a, b)
	return fposmod(float(a), float(b))
static func power(a, b): return pow(a, b)
static func neg(a): return -a
static func py_len(a):
	if a is Vector3: return 3
	if a is Vector2: return 2
	return a.size() if not a is String else a.length()
static func py_list(a):
	if a is Vector3: return [a.x,a.y,a.z]
	if a is Vector2: return [a.x,a.y]
	return Array(a) if not a is Dictionary else a.keys()
static func py_tuple(a): return py_list(a)
static func py_dict(a = {}): return a.duplicate(true) if a is Dictionary else from_pairs(a)
static func py_set(a):
	var result = []
	for x in a:
		if x not in result: result.append(x)
	return result
static func py_min(a, b = null, c = null, d = null):
	var values = a if a is Array and b == null else [a, b, c, d].filter(func(x): return x != null)
	return values.min()
static func py_max(a, b = null, c = null, d = null):
	var values = a if a is Array and b == null else [a, b, c, d].filter(func(x): return x != null)
	return values.max()
static func py_sum(a):
	var result = 0.0
	for x in a: result += x
	return result
static func py_all(a):
	for x in a:
		if not truth(x): return false
	return true
static func py_any(a):
	for x in a:
		if truth(x): return true
	return false
static func py_zip(a, b, c = null):
	var result = []
	for i in range(mini(py_len(a), py_len(b)) if c == null else mini(mini(py_len(a), py_len(b)), py_len(c))):
		result.append([a[i], b[i]] if c == null else [a[i], b[i], c[i]])
	return result
static func py_enumerate(a):
	var result = []
	for i in range(a.size()): result.append([i, a[i]])
	return result
static func py_reversed(a):
	var result = Array(a).duplicate()
	result.reverse()
	return result
static func py_sorted(a, key = null, reverse = false):
	var result = Array(a).duplicate()
	if key is Callable: result.sort_custom(func(x, y): return key.call(x) < key.call(y))
	else: result.sort()
	if reverse: result.reverse()
	return result
static func py_round(a, digits = 0): return round(a * pow(10.0, digits)) / pow(10.0, digits)
static func items(a):
	var result = []
	for key in a: result.append([key, a[key]])
	return result
static func from_pairs(a):
	var result = {}
	for pair in a: result[pair[0]] = pair[1]
	return result
static func map_array(a, callback):
	var result = []
	for x in a: result.append(callback.call(x))
	return result
static func flat_map(a, callback):
	var result = []
	for x in a: result.append_array(callback.call(x))
	return result
static func slice_array(a, first = null, last = null, stride = null):
	var count = a.size()
	var step = 1 if stride == null else int(stride)
	var begin = (0 if step > 0 else count - 1) if first == null else int(first)
	var end = (count if step > 0 else -1) if last == null else int(last)
	if first != null and begin < 0: begin += count
	if last != null and end < 0: end += count
	var result = []
	for i in range(begin, end, step):
		if i >= 0 and i < count: result.append(a[i])
	return result
static func hypot(a, b): return sqrt(a * a + b * b)
static func dist(a, b):
	var result = 0.0
	for i in range(a.size()): result += pow(a[i] - b[i], 2)
	return sqrt(result)
static func copysign(a, b): return abs(a) * (-1 if b < 0 else 1)
static func bisect_right(a, x):
	var i = 0
	while i < a.size() and a[i] <= x: i += 1
	return i
static func vector(a): return Vector3(a[0], a[1], a[2]) if a is Array else a
static func track_euler(direction):
	var d = vector(direction).normalized()
	var z = d
	var x = Vector3.UP.cross(z).normalized()
	if x.length_squared() < 0.000001: x = Vector3.RIGHT
	var y = z.cross(x)
	var e = Basis(x, y, z).get_euler()
	return [e.x, e.y, e.z]

# Python's MT19937 and integer seeding keep existing seed-based recipes stable.
class RandomSequence:
	var state = []
	var cursor = 624
	func _init(seed_value = 0):
		state.resize(624)
		state[0] = 19650218
		for i in range(1, 624): state[i] = (1812433253 * (state[i - 1] ^ (state[i - 1] >> 30)) + i) & 0xffffffff
		var key = [absi(int(seed_value)) & 0xffffffff]
		if absi(int(seed_value)) > 0xffffffff: key.append(absi(int(seed_value)) >> 32)
		var i = 1
		var j = 0
		for _k in range(maxi(624, key.size())):
			state[i] = ((state[i] ^ ((state[i - 1] ^ (state[i - 1] >> 30)) * 1664525)) + key[j] + j) & 0xffffffff
			i += 1
			j = (j + 1) % key.size()
			if i >= 624: state[0] = state[623]; i = 1
		for _k in range(623):
			state[i] = ((state[i] ^ ((state[i - 1] ^ (state[i - 1] >> 30)) * 1566083941)) - i) & 0xffffffff
			i += 1
			if i >= 624: state[0] = state[623]; i = 1
		state[0] = 0x80000000
	func bits32():
		if cursor >= 624:
			for i in range(624):
				var y = (state[i] & 0x80000000) | (state[(i + 1) % 624] & 0x7fffffff)
				state[i] = state[(i + 397) % 624] ^ (y >> 1) ^ (0x9908b0df if y & 1 else 0)
			cursor = 0
		var y = state[cursor]
		cursor += 1
		y ^= y >> 11
		y ^= (y << 7) & 0x9d2c5680
		y ^= (y << 15) & 0xefc60000
		y ^= y >> 18
		return y & 0xffffffff
	func random_value(): return ((bits32() >> 5) * 67108864.0 + (bits32() >> 6)) / 9007199254740992.0
	func uniform(a, b): return a + (b - a) * random_value()
	func randrange(n):
		var width = 1
		while (1 << width) <= n: width += 1
		var value = bits32() >> (32 - width)
		while value >= n: value = bits32() >> (32 - width)
		return value
	func choice(a): return a[randrange(a.size())]
