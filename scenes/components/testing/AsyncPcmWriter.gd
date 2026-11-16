extends RefCounted
## The game thread only transfers immutable PCM chunks; one worker owns the file.
var _thread := Thread.new()
var _mutex := Mutex.new()
var _available := Semaphore.new()
var _opened := Semaphore.new()
var _chunks: Array[PackedByteArray] = []
var _closing := false
var _error: Error = OK
var _bytes := 0
var _queued_bytes := 0

func start(path: String) -> Error:
	var started := _thread.start(_write.bind(path))
	if started != OK: return started
	_opened.wait()
	return int(stats().error) as Error

func enqueue(chunk: PackedByteArray) -> void:
	if chunk.is_empty(): return
	_mutex.lock()
	_chunks.append(chunk)
	_queued_bytes += chunk.size()
	_mutex.unlock()
	_available.post()

func stats() -> Dictionary:
	_mutex.lock()
	var result := {"bytes_written": _bytes, "bytes_queued": _queued_bytes, "error": _error}
	_mutex.unlock()
	return result

func finish() -> Dictionary:
	if _thread.is_started():
		_mutex.lock()
		_closing = true
		_mutex.unlock()
		_available.post()
		_thread.wait_to_finish()
	return stats()

func _write(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_mutex.lock()
	_error = FileAccess.get_open_error() if file == null else OK
	_mutex.unlock()
	_opened.post()
	if file == null: return
	var last_flush := Time.get_ticks_msec()
	while true:
		_available.wait()
		_mutex.lock()
		var batch := _chunks
		_chunks = []
		var closing := _closing
		_mutex.unlock()
		var written := 0
		for chunk in batch:
			file.store_buffer(chunk)
			written += chunk.size()
		if closing or Time.get_ticks_msec() - last_flush >= 100:
			file.flush()
			last_flush = Time.get_ticks_msec()
		_mutex.lock()
		_bytes += written
		_queued_bytes -= written
		_error = file.get_error()
		_mutex.unlock()
		if closing: break
	file.close()
