extends Node

signal cover_loaded(chart: Chart, texture: Texture2D)
signal cover_failed(chart: Chart)

var worker := Thread.new()
var mutex := Mutex.new()
var semaphore := Semaphore.new()
var queued_charts: Array[Chart] = []
var queued_ids := {}
var completed_results: Array[Dictionary] = []
var is_stopping := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	worker.start(Callable(self, "_worker_loop"))


func _exit_tree() -> void:
	is_stopping = true
	semaphore.post()

	if worker.is_started():
		worker.wait_to_finish()


func request_cover(chart: Chart) -> void:
	if chart == null or chart.cover_image != null:
		return

	var cover_path := chart.get_cover_path()
	if cover_path.is_empty():
		return

	var chart_id := chart.get_instance_id()

	mutex.lock()
	if queued_ids.has(chart_id):
		mutex.unlock()
		return

	queued_ids[chart_id] = true
	queued_charts.append(chart)
	mutex.unlock()
	semaphore.post()


func _process(_delta: float) -> void:
	var results: Array[Dictionary] = []

	mutex.lock()
	if not completed_results.is_empty():
		results = completed_results
		completed_results = []
	mutex.unlock()

	for result in results:
		var chart: Chart = result.get("chart")
		if chart == null:
			continue

		mutex.lock()
		queued_ids.erase(chart.get_instance_id())
		mutex.unlock()

		var image: Image = result.get("image")
		if image == null:
			cover_failed.emit(chart)
			continue

		if chart.cover_image == null:
			chart.cover_image = ImageTexture.create_from_image(image)

		cover_loaded.emit(chart, chart.cover_image)


func _worker_loop() -> void:
	while true:
		semaphore.wait()

		if is_stopping:
			return

		var chart: Chart = null

		mutex.lock()
		if not queued_charts.is_empty():
			chart = queued_charts.pop_front()
		mutex.unlock()

		if chart == null:
			continue

		var image := chart.load_cover_image_data()

		mutex.lock()
		completed_results.append({
			"chart": chart,
			"image": image,
		})
		mutex.unlock()
