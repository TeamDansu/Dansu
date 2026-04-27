extends Control
class_name SongSelectListView

signal item_clicked(item: SongListItem)

@export var scroll_container: ScrollContainer
@export var content_root: VBoxContainer
@export var top_spacer: Control
@export var chart_list: GridContainer
@export var bottom_spacer: Control
@export var thumb_scene: PackedScene
@export var overscan_rows: int = 2

var thumb_nodes: Array[Button] = []
var cached_thumb_nodes: Array[Button] = []
var visible_items: Array[SongListItem] = []

var row_height: float = 1.0
var column_count: int = 1
var visible_row_count: int = 1
var thumb_min_size := Vector2(128, 128)
var pool_capacity: int = 0
var last_start_row := -1
var last_display_count := -1
var last_column_count := -1
var _is_ready := false
var _layout_refresh_queued := false
var _last_scrollbar_visible := false


func _ready() -> void:
	resized.connect(_on_view_resized)

	if scroll_container != null:
		scroll_container.resized.connect(_on_view_resized)
		var v_scroll_bar := scroll_container.get_v_scroll_bar()
		if v_scroll_bar != null:
			v_scroll_bar.value_changed.connect(_on_scroll_value_changed)

	await get_tree().process_frame
	_is_ready = true
	_rebuild_layout()


func set_items(items: Array[SongListItem]) -> void:
	visible_items = items
	last_start_row = -1
	last_display_count = -1
	last_column_count = -1

	if scroll_container != null:
		scroll_container.scroll_vertical = 0

	if _is_ready:
		_rebuild_layout()


func _on_view_resized() -> void:
	_queue_layout_refresh()


func _on_scroll_value_changed(_value: float) -> void:
	_refresh_visible_nodes()


func _queue_layout_refresh() -> void:
	if _layout_refresh_queued:
		return

	_layout_refresh_queued = true
	call_deferred("_rebuild_layout")


func _rebuild_layout() -> void:
	_layout_refresh_queued = false

	if not _has_required_nodes():
		return

	_update_grid_metrics()

	var target_thumb_count = max((visible_row_count + overscan_rows) * column_count, 0)
	pool_capacity = target_thumb_count
	_ensure_thumb_pool_size(target_thumb_count)
	_update_grid_metrics()
	_refresh_visible_nodes()


func _has_required_nodes() -> bool:
	return (
		scroll_container != null
		and content_root != null
		and top_spacer != null
		and chart_list != null
		and bottom_spacer != null
		and thumb_scene != null
	)


func _update_grid_metrics() -> void:
	if not thumb_nodes.is_empty():
		var first_thumb := thumb_nodes[0] as Control
		if first_thumb != null:
			thumb_min_size = first_thumb.get_combined_minimum_size()

	var v_separation := float(chart_list.get_theme_constant("v_separation"))
	var available_width := _get_content_width()

	column_count = chart_list.columns

	row_height = max(thumb_min_size.y + v_separation, 1.0)
	visible_row_count = max(int(ceil(scroll_container.size.y / row_height)), 1)

	content_root.custom_minimum_size.x = available_width
	chart_list.custom_minimum_size.x = available_width


func _get_content_width() -> float:
	if scroll_container == null:
		return max(size.x, 1.0)

	var width := scroll_container.size.x
	var v_scroll_bar := scroll_container.get_v_scroll_bar()
	if v_scroll_bar != null and v_scroll_bar.visible:
		width -= v_scroll_bar.size.x

	return max(width, 1.0)


func _ensure_thumb_pool_size(target_count: int) -> void:
	while thumb_nodes.size() > target_count:
		var thumb = thumb_nodes.pop_back()
		if thumb == null:
			continue
		chart_list.remove_child(thumb)
		thumb.visible = false
		cached_thumb_nodes.append(thumb)

	while thumb_nodes.size() < target_count:
		var thumb: Button = null
		if not cached_thumb_nodes.is_empty():
			thumb = cached_thumb_nodes.pop_back()
		else:
			thumb = thumb_scene.instantiate() as Button
		if thumb == null:
			return

		chart_list.add_child(thumb)
		thumb_nodes.append(thumb)

		var thumb_control := thumb as Control
		if thumb_control != null:
			thumb_min_size = thumb_control.get_combined_minimum_size()

		if thumb.has_signal("item_pressed") and not thumb.item_pressed.is_connected(_on_thumb_item_pressed):
			thumb.item_pressed.connect(_on_thumb_item_pressed)


func _refresh_visible_nodes() -> void:
	if not _has_required_nodes():
		return

	var total_rows := _get_total_row_count()
	var pool_row_count = max(int(ceil(float(max(pool_capacity, 1)) / float(column_count))), 1)
	var max_start_row = max(total_rows - pool_row_count, 0)
	var start_row := 0
	if row_height > 0.0 and total_rows > 0:
		start_row = clamp(
			int(floor(scroll_container.scroll_vertical / row_height)),
			0,
			max_start_row
		)

	var start_index := start_row * column_count
	var display_count = min(max(visible_items.size() - start_index, 0), pool_capacity)

	var displayed_rows := 0
	if display_count > 0:
		displayed_rows = int(ceil(float(display_count) / float(column_count)))

	var needs_full_refresh = (
		last_start_row == -1
		or last_column_count != column_count
		or abs(start_row - last_start_row) * column_count >= max(thumb_nodes.size(), 1)
	)

	if needs_full_refresh:
		_bind_visible_range(start_index)
	elif start_row != last_start_row:
		_shift_visible_range(start_row - last_start_row, start_index, display_count, last_display_count)

	top_spacer.custom_minimum_size.y = start_row * row_height + 20
	bottom_spacer.custom_minimum_size.y = max(total_rows - start_row - displayed_rows, 0) * row_height
	chart_list.visible = display_count > 0
	last_start_row = start_row
	last_display_count = display_count
	last_column_count = column_count

	var has_scrollbar := false
	var v_scroll_bar := scroll_container.get_v_scroll_bar()
	if v_scroll_bar != null:
		has_scrollbar = v_scroll_bar.visible

	if has_scrollbar != _last_scrollbar_visible:
		_last_scrollbar_visible = has_scrollbar
		_queue_layout_refresh()


func _get_total_row_count() -> int:
	if visible_items.is_empty():
		return 0

	return int(ceil(float(visible_items.size()) / float(column_count)))


func _bind_visible_range(start_index: int) -> void:
	for i in range(thumb_nodes.size()):
		_bind_thumb(thumb_nodes[i], start_index + i)


func _shift_visible_range(delta_rows: int, start_index: int, _display_count: int, previous_display_count: int) -> void:
	var shift_count = abs(delta_rows) * column_count

	if shift_count <= 0:
		return

	if delta_rows > 0:
		var moved_nodes: Array[Button] = []
		for i in range(shift_count):
			var thumb := thumb_nodes[0]
			thumb_nodes.remove_at(0)
			moved_nodes.append(thumb)

		for thumb in moved_nodes:
			thumb_nodes.append(thumb)
			chart_list.move_child(thumb, chart_list.get_child_count() - 1)

		var rebind_start = start_index + max(previous_display_count, 0) - shift_count
		for i in range(moved_nodes.size()):
			_bind_thumb(moved_nodes[i], rebind_start + i)
	else:
		var moved_nodes: Array[Button] = []
		for i in range(shift_count):
			var thumb := thumb_nodes[thumb_nodes.size() - 1]
			thumb_nodes.remove_at(thumb_nodes.size() - 1)
			moved_nodes.push_front(thumb)

		for i in range(moved_nodes.size() - 1, -1, -1):
			chart_list.move_child(moved_nodes[i], 0)

		thumb_nodes = moved_nodes + thumb_nodes

		for i in range(moved_nodes.size()):
			_bind_thumb(moved_nodes[i], start_index + i)


func _bind_thumb(thumb: Button, item_index: int) -> void:
	if thumb == null:
		return

	if item_index >= 0 and item_index < visible_items.size():
		thumb.visible = true
		if thumb.has_method("set_item"):
			thumb.set_item(visible_items[item_index])
	else:
		thumb.visible = false
		if thumb.has_method("set_item"):
			thumb.set_item(null)


func _on_thumb_item_pressed(item: SongListItem) -> void:
	item_clicked.emit(item)
