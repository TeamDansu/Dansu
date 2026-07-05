extends Control

@export var progress_bar : ProgressBar
@export var current_chartset_label: Label
@export var search_input: LineEdit
@export var sort_option_button: OptionButton
@export var chart_scroll: Control

var progress: float = 0.0
var loading_timer = 0.0

func _ready() -> void:
	if progress_bar == null:
		progress_bar = $LoadingProgress/ProgressBar
	if current_chartset_label == null:
		current_chartset_label = $LoadingProgress/Label
	if search_input == null:
		search_input = $Charts/Search/SearchArea/SearchInput
	if sort_option_button == null:
		sort_option_button = $Charts/Search/SearchArea/SortOptionButton
	if chart_scroll == null:
		chart_scroll = $Charts
	
	if Game.stage == Game.GameStage.Loading:
		CM._load(false)
		
	
	CM.progress_changed.connect(_update_progress)
	CM.loading_finished.connect(_loading_finished)

	if search_input != null:
		search_input.text_changed.connect(_on_search_text_changed)

	if sort_option_button != null:
		sort_option_button.item_selected.connect(_on_sort_item_selected)
		_setup_sort_options()

func _process(delta):
	loading_timer += delta
	
	if Input.is_action_just_pressed("shortcut_enter_editor"):
		CM.parse_selected_chart()
		Transition.transition_to("res://scenes/editor/editor_scene.tscn",1)

func _update_progress(_progress: float) -> void:
	progress = _progress
	if progress_bar != null:
		progress_bar.value = _progress

func _loading_finished() -> void:
	print("[charts] load time %f" %loading_timer)
	if chart_scroll != null and chart_scroll.has_method("rebuild_items"):
		chart_scroll.rebuild_items()
	if current_chartset_label != null:
		current_chartset_label.text = "enjoy!"
	$Animations.loading_done()


func _setup_sort_options() -> void:
	if sort_option_button == null:
		return

	sort_option_button.clear()
	sort_option_button.add_item("title", 0)
	sort_option_button.add_item("artist", 1)
	sort_option_button.add_item("rating", 2)
	sort_option_button.select(0)


func _on_search_text_changed(new_text: String) -> void:
	if chart_scroll != null and chart_scroll.has_method("set_search_text"):
		chart_scroll.set_search_text(new_text)


func _on_sort_item_selected(index: int) -> void:
	if sort_option_button == null:
		return

	var sort_id := sort_option_button.get_item_id(index)
	if chart_scroll != null and chart_scroll.has_method("set_sort_mode"):
		chart_scroll.set_sort_mode(sort_id)
