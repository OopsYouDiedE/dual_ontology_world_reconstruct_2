extends RefCounted
## Building scene YAML: block/flow collections, quoted/scalar values and comments.
## JSON documents are YAML 1.2 documents and are accepted without normalization.
var lines: Array = []
var cursor = 0
var error = ""

func parse(text: String):
	var json = JSON.new()
	if json.parse(text)==OK: return json.data
	lines = []
	cursor = 0
	error = ""
	for raw in text.split("\n"):
		var stripped = uncomment(raw.trim_suffix("\r"))
		if stripped.strip_edges() in ["","---","..."]: continue
		var indent = stripped.length()-stripped.lstrip(" ").length()
		var content = stripped.substr(indent)
		if content.begins_with("- ") and delimiter(content.substr(2),":")>=0:
			lines.append({"indent":indent,"text":"-"})
			lines.append({"indent":indent+2,"text":content.substr(2)})
		else: lines.append({"indent":indent,"text":content})
	if lines.is_empty(): return null
	var result = block(lines[0].indent)
	if cursor<lines.size(): error = "YAML 缩进或集合格式无效"
	return result if error.is_empty() else null

func uncomment(text: String) -> String:
	var quote = ""
	var escape = false
	for i in range(text.length()):
		var ch = text[i]
		if escape: escape = false; continue
		if quote=="\"" and ch=="\\": escape = true; continue
		if not quote.is_empty():
			if ch==quote: quote = ""
		elif ch in ["\"","'"]: quote = ch
		elif ch=="#" and (i==0 or text[i-1] in [" ","\t"]): return text.left(i).strip_edges(false,true)
	return text.strip_edges(false,true)

func delimiter(text: String, target: String) -> int:
	var quote = ""
	var escape = false
	var depth = 0
	for i in range(text.length()):
		var ch = text[i]
		if escape: escape = false; continue
		if quote=="\"" and ch=="\\": escape = true; continue
		if not quote.is_empty():
			if ch==quote: quote = ""
		elif ch in ["\"","'"]: quote = ch
		elif ch in ["[","{"]: depth += 1
		elif ch in ["]","}"]: depth -= 1
		elif ch==target and depth==0: return i
	return -1

func parts(text: String) -> Array:
	var result = []
	var remaining = text.strip_edges()
	while not remaining.is_empty():
		var i = delimiter(remaining,",")
		if i<0: result.append(remaining.strip_edges()); break
		result.append(remaining.left(i).strip_edges())
		remaining = remaining.substr(i+1).strip_edges()
	return result

func scalar(text: String):
	var value = text.strip_edges()
	if value in ["null","Null","NULL","~",""]: return null
	if value.to_lower()=="true": return true
	if value.to_lower()=="false": return false
	if value.is_valid_int(): return value.to_int()
	if value.is_valid_float(): return value.to_float()
	if value.begins_with("\""):
		var parsed = JSON.new()
		if parsed.parse(value)==OK: return parsed.data
		error = "YAML 字符串格式无效"
		return null
	if value.begins_with("'") and value.ends_with("'"): return value.substr(1,value.length()-2).replace("''","'")
	if value.begins_with("[") and value.ends_with("]"):
		var result = []
		for part in parts(value.substr(1,value.length()-2)): result.append(scalar(part))
		return result
	if value.begins_with("{") and value.ends_with("}"):
		var result = {}
		for part in parts(value.substr(1,value.length()-2)):
			var i = delimiter(part,":")
			if i<0: error = "YAML 映射格式无效"; return null
			result[str(scalar(part.left(i)))] = scalar(part.substr(i+1))
		return result
	return value

func block(indent: int):
	var sequence = lines[cursor].text=="-" or lines[cursor].text.begins_with("- ")
	var result = [] if sequence else {}
	while cursor<lines.size() and lines[cursor].indent==indent:
		var content: String = lines[cursor].text
		cursor += 1
		if sequence:
			if not (content=="-" or content.begins_with("- ")): error = "YAML 列表格式无效"; return null
			var tail = content.substr(1).strip_edges()
			result.append(block(lines[cursor].indent) if tail.is_empty() and cursor<lines.size() and lines[cursor].indent>indent else scalar(tail))
		else:
			var i = delimiter(content,":")
			if i<0: error = "YAML 映射缺少冒号"; return null
			var key = str(scalar(content.left(i)))
			var tail = content.substr(i+1).strip_edges()
			if tail.is_empty() and cursor<lines.size() and (lines[cursor].indent>indent or (lines[cursor].indent==indent and lines[cursor].text.begins_with("-"))): result[key] = block(lines[cursor].indent)
			else: result[key] = scalar(tail)
	return result

static func dump(value, depth: int = 0) -> String:
	if depth>=3 or (value is Array and value.is_empty()) or (value is Dictionary and value.is_empty()): return JSON.stringify(value)
	var output = []
	var padding = "  ".repeat(depth)
	if value is Dictionary:
		for key in value:
			var child = value[key]
			var nested = (child is Dictionary or child is Array) and not child.is_empty() and depth+1<3
			output.append(padding+JSON.stringify(str(key))+":"+("\n"+dump(child,depth+1) if nested else " "+JSON.stringify(child)))
	elif value is Array:
		for child in value:
			var nested = (child is Dictionary or child is Array) and not child.is_empty() and depth+1<3
			output.append(padding+"-"+("\n"+dump(child,depth+1) if nested else " "+JSON.stringify(child)))
	else: return JSON.stringify(value)
	return "\n".join(output)
