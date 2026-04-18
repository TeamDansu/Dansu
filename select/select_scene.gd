extends Control

@export var search_input: LineEdit
@export var sort_option_button: OptionButton
@export var list_view: SongSelectListView

var controller := SongSelectController.new()

func _ready() -> void:
	_setup_sort_options()

	controller.visible_items_changed.connect(_on_visible_items_changed)
	list_view.item_clicked.connect(_on_item_clicked)

	search_input.text_changed.connect(_on_search_text_changed)
	sort_option_button.item_selected.connect(_on_sort_item_selected)
	controller.set_chartsets(CM.chartsets)


func _setup_sort_options() -> void:
	if sort_option_button:
		sort_option_button.clear()
		sort_option_button.add_item("Title", SongSelectController.SortMode.TITLE)
		sort_option_button.add_item("Artist", SongSelectController.SortMode.ARTIST)
		sort_option_button.add_item("Rating", SongSelectController.SortMode.RATING)
		sort_option_button.select(0)


func _on_search_text_changed(new_text: String) -> void:
	controller.set_search_word(new_text)


func _on_sort_item_selected(index: int) -> void:
	var id := sort_option_button.get_item_id(index)
	controller.set_sort_mode(id as SongSelectController.SortMode)


func _on_visible_items_changed(items: Array[SongListItem]) -> void:
	list_view.set_items(items)


func _on_item_clicked(item: SongListItem) -> void:
	if item == null:
		return

	CM.selected_chartset = item.chartset
	CM.selected_chart = item.primary_chart
