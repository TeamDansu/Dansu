extends Control

@export var content : Control

enum SortMode {
	TITLE,
	ARTIST,
	RATING,
}

var nodes: Array[Node] = []
var visible_items: Array[SongListItem] = []

var data_count := 0
var item_height := 0.0
var step := 0.0

var scroll := 0.0
var target_scroll := 0.0

var smooth_speed := 12.0
var search_text := ""
var sort_mode: SortMode = SortMode.TITLE
var _last_cover_request_ids: Array[int] = []


func _ready() -> void:
	CM.loading_finished.connect(_init_charts)
	CM.chart_update.connect(_on_chart_update)


func _init_charts() -> void:
	if content.get_child_count() == 0:
		return

	nodes = content.get_children()

	var first := nodes[0] as Control
	item_height = first.size.y
	step = item_height + 10.0

	for i in range(nodes.size()):
		nodes[i].position.y = i * step

	rebuild_items()


func rebuild_items() -> void:
	var previous_chart := CM.selected_chart
	var previous_chartset := CM.selected_chartset

	visible_items = _build_visible_items()
	data_count = visible_items.size()

	var selected_index := _find_best_selection_index(previous_chart, previous_chartset)
	if selected_index == -1 and data_count > 0:
		selected_index = 0

	_apply_selection_from_index(selected_index)
	_center_on_index(selected_index)
	_apply_all()
	_queue_visible_cover_requests()

func _on_chart_update(_chartsets) -> void:
	if nodes.is_empty():
		_init_charts()
		return
	rebuild_items()


func set_search_text(value: String) -> void:
	search_text = value
	rebuild_items()


func set_sort_mode(value: int) -> void:
	sort_mode = value as SortMode
	rebuild_items()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_scroll += step
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_scroll -= step


func _process(delta: float) -> void:
	if data_count <= 0:
		return

	target_scroll = clamp(target_scroll, 0.0, float(max(data_count - 1, 0)) * step)
	var previous_scroll := scroll
	scroll = lerp(scroll, target_scroll, 1.0 - exp(-smooth_speed * delta))
	_update()
	if not is_equal_approx(previous_scroll, scroll):
		_sync_visible_hover_states()


func _update() -> void:
	var center := size.y * 0.5 - item_height * 0.5
	content.position.y = center - scroll
	_recycle()


func _recycle() -> void:
	var changed := false
	for n in nodes:
		var global_y = n.position.y + content.position.y

		if global_y > size.y + step:
			n.position.y -= step * nodes.size()
			_update_node(n as Control)
			changed = true
		elif global_y < -step:
			n.position.y += step * nodes.size()
			_update_node(n as Control)
			changed = true

	if changed:
		_queue_visible_cover_requests()


func _update_node(node: Control) -> void:
	if node == null:
		return

	var index := int(round(node.position.y / step))
	if index < 0 or index >= data_count:
		node.visible = false
		if node.has_method("set_item"):
			node.set_item(null)
		return

	node.visible = true
	node.name = str(index)

	if node.has_method("set_item"):
		node.set_item(visible_items[index])


func _apply_all() -> void:
	for i in range(nodes.size()):
		_update_node(nodes[i] as Control)
	_sync_visible_hover_states()


func _queue_visible_cover_requests() -> void:
	var charts := _collect_visible_cover_charts()
	var chart_ids: Array[int] = []

	for chart in charts:
		chart_ids.append(chart.get_instance_id())

	if chart_ids == _last_cover_request_ids:
		return

	_last_cover_request_ids = chart_ids
	CoverLoader.replace_queue(charts)


func _collect_visible_cover_charts() -> Array[Chart]:
	var entries: Array[Dictionary] = []
	var center_y := size.y * 0.5
	var selected_chart := CM.selected_chart

	for node in nodes:
		var control := node as Control
		if control == null or not control.visible:
			continue

		var chart := _get_node_primary_chart(control)
		if chart == null:
			continue

		var node_center_y := control.position.y + content.position.y + item_height * 0.5
		entries.append({
			"chart": chart,
			"distance": absf(node_center_y - center_y),
			"is_selected": chart == selected_chart,
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["is_selected"] != b["is_selected"]:
			return a["is_selected"]
		return a["distance"] < b["distance"]
	)

	var charts: Array[Chart] = []
	for entry in entries:
		charts.append(entry["chart"])
	return charts


func _get_node_primary_chart(node: Control) -> Chart:
	if node == null:
		return null

	var item_value = node.get("item")
	if item_value is SongListItem:
		return item_value.primary_chart

	var current_chart = node.get("current_cover_chart")
	if current_chart is Chart:
		return current_chart

	return null


func _build_visible_items() -> Array[SongListItem]:
	var items: Array[SongListItem] = []
	var lowered_word := search_text.strip_edges().to_lower()

	for chartset in CM.chartsets:
		var matched_charts: Array[Chart] = []
		for chart in chartset.charts:
			if lowered_word.is_empty() or chart.search_string_lower.contains(lowered_word):
				matched_charts.append(chart)

		if matched_charts.is_empty():
			continue

		matched_charts.sort_custom(_sort_chart_by_rating)

		if sort_mode == SortMode.RATING:
			for chart in matched_charts:
				var chart_item := SongListItem.new()
				chart_item.type = SongListItem.ItemType.CHART
				chart_item.chartset = chartset
				chart_item.charts = [chart]
				chart_item.primary_chart = chart
				items.append(chart_item)
		else:
			var item := SongListItem.new()
			item.type = SongListItem.ItemType.CHARTSET
			item.chartset = chartset
			item.charts = matched_charts
			item.primary_chart = _pick_primary_chart(matched_charts)
			items.append(item)

	match sort_mode:
		SortMode.TITLE:
			items.sort_custom(_sort_item_by_title)
		SortMode.ARTIST:
			items.sort_custom(_sort_item_by_artist)
		SortMode.RATING:
			items.sort_custom(_sort_item_by_rating_desc)

	return items


func _pick_primary_chart(charts: Array[Chart]) -> Chart:
	if charts.is_empty():
		return null
	return charts[0]


func _sort_chart_by_rating(a: Chart, b: Chart) -> bool:
	return a.rating < b.rating


func _sort_item_by_title(a: SongListItem, b: SongListItem) -> bool:
	return _get_item_title(a).to_lower() < _get_item_title(b).to_lower()


func _sort_item_by_artist(a: SongListItem, b: SongListItem) -> bool:
	return _get_item_artist(a).to_lower() < _get_item_artist(b).to_lower()


func _sort_item_by_rating_desc(a: SongListItem, b: SongListItem) -> bool:
	var ar := _get_item_rating(a)
	var br := _get_item_rating(b)
	if is_equal_approx(ar, br):
		return _get_item_title(a).to_lower() < _get_item_title(b).to_lower()
	return ar > br


func _get_item_title(item: SongListItem) -> String:
	if item == null or item.primary_chart == null:
		return ""
	return item.primary_chart.title


func _get_item_artist(item: SongListItem) -> String:
	if item == null or item.primary_chart == null:
		return ""
	return item.primary_chart.artist


func _get_item_rating(item: SongListItem) -> float:
	if item == null or item.primary_chart == null:
		return 0.0
	return item.primary_chart.rating


func _find_best_selection_index(previous_chart: Chart, previous_chartset: ChartSet) -> int:
	if previous_chart != null:
		for i in range(visible_items.size()):
			var item := visible_items[i]
			if item.primary_chart == previous_chart or item.charts.has(previous_chart):
				return i

	if previous_chartset != null:
		for i in range(visible_items.size()):
			var item := visible_items[i]
			if item.chartset == previous_chartset:
				return i

	return -1


func _apply_selection_from_index(index: int) -> void:
	if index < 0 or index >= visible_items.size():
		CM.select_chartset(null)
		CM.select_chart(null)
		return

	var item := visible_items[index]
	CM.select_chartset(item.chartset)
	CM.select_chart(item.primary_chart)


func _center_on_index(index: int) -> void:
	if index < 0 or data_count <= 0:
		target_scroll = 0.0
		scroll = 0.0
		return

	var centered_scroll := index * step
	var max_scroll := float(max(data_count - 1, 0)) * step
	target_scroll = clamp(centered_scroll, 0.0, max_scroll)
	scroll = target_scroll

func _sync_visible_hover_states() -> void:
	if not get_viewport():
		return
	var mouse_position := get_viewport().get_mouse_position()

	for node in nodes:
		if node != null and node.has_method("sync_hover_state"):
			node.sync_hover_state(mouse_position)
