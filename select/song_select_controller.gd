extends RefCounted
class_name SongSelectController

signal visible_items_changed(items: Array[SongListItem])

enum SortMode {
	TITLE,
	ARTIST,
	RATING,
}

var chartsets: Array[ChartSet] = []
var current_sort_mode: SortMode = SortMode.TITLE
var rating_min: float = 0.0
var rating_max: float = 999.0
var search_word: String = ""

var visible_items: Array[SongListItem] = []


func set_chartsets(value: Array[ChartSet]) -> void:
	chartsets = value
	rebuild()


func set_search_word(value: String) -> void:
	search_word = value
	rebuild()


func set_sort_mode(value: SortMode) -> void:
	current_sort_mode = value
	rebuild()


func set_rating_filter(min_value: float, max_value: float) -> void:
	rating_min = min_value
	rating_max = max_value
	rebuild()


func rebuild() -> void:
	visible_items.clear()

	match current_sort_mode:
		SortMode.TITLE, SortMode.ARTIST:
			_build_chartset_items()

		SortMode.RATING:
			_build_chart_items()

	_sort_visible_items()
	visible_items_changed.emit(visible_items)


func _build_chartset_items() -> void:
	var lowered_word := search_word.to_lower()

	for chartset in chartsets:
		var matched_charts: Array[Chart] = []

		for chart: Chart in chartset.charts:
			if _is_chart_match(chart, lowered_word):
				matched_charts.append(chart)

		if matched_charts.is_empty():
			continue

		var item := SongListItem.new()
		item.type = SongListItem.ItemType.CHARTSET
		item.chartset = chartset
		item.charts = matched_charts
		item.primary_chart = _pick_primary_chart_for_chartset(matched_charts)
		visible_items.append(item)


func _build_chart_items() -> void:
	var lowered_word := search_word.to_lower()

	for chartset in chartsets:
		for chart: Chart in chartset.charts:
			if not _is_chart_match(chart, lowered_word):
				continue

			var item := SongListItem.new()
			item.type = SongListItem.ItemType.CHART
			item.chartset = chartset
			item.charts = [chart]
			item.primary_chart = chart
			visible_items.append(item)


func _is_chart_match(chart: Chart, lowered_word: String) -> bool:
	if chart == null:
		return false

	if chart.rating < rating_min or chart.rating > rating_max:
		return false

	if lowered_word.is_empty():
		return true

	return chart.search_string_lower.contains(lowered_word)


func _pick_primary_chart_for_chartset(charts: Array[Chart]) -> Chart:
	if charts.is_empty():
		return null

	return charts[0]


func _sort_visible_items() -> void:
	match current_sort_mode:
		SortMode.TITLE:
			visible_items.sort_custom(_sort_by_title)

		SortMode.ARTIST:
			visible_items.sort_custom(_sort_by_artist)

		SortMode.RATING:
			visible_items.sort_custom(_sort_by_rating_desc)


func _sort_by_title(a: SongListItem, b: SongListItem) -> bool:
	var at := _get_item_title(a).to_lower()
	var bt := _get_item_title(b).to_lower()
	return at < bt


func _sort_by_artist(a: SongListItem, b: SongListItem) -> bool:
	var aa := _get_item_artist(a).to_lower()
	var ba := _get_item_artist(b).to_lower()
	return aa < ba


func _sort_by_rating_desc(a: SongListItem, b: SongListItem) -> bool:
	var ar := _get_item_rating(a)
	var br := _get_item_rating(b)
	if ar == br:
		var ast = _get_search_string(a)
		var bst = _get_search_string(b)
		return ast < bst
	return ar > br


func _get_item_title(item: SongListItem) -> String:
	if item == null or item.primary_chart == null:
		return ""
	return item.primary_chart.title

func _get_search_string(item: SongListItem) -> String:
	if item == null or item.primary_chart == null:
		return ""
	return item.primary_chart.search_string


func _get_item_artist(item: SongListItem) -> String:
	if item == null or item.primary_chart == null:
		return ""
	return item.primary_chart.artist


func _get_item_rating(item: SongListItem) -> float:
	if item == null or item.primary_chart == null:
		return 0.0
	return item.primary_chart.rating
