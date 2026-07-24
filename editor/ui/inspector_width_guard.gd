extends Control
class_name InspectorWidthGuard


func _ready() -> void:
	_watch_subtree(self)


func _watch_subtree(node: Node) -> void:
	if not is_instance_valid(node):
		return
	_configure_control(node)
	if not node.child_entered_tree.is_connected(_on_child_entered_tree):
		node.child_entered_tree.connect(_on_child_entered_tree)
	for child in node.get_children():
		_watch_subtree(child)


func _on_child_entered_tree(node: Node) -> void:
	call_deferred("_watch_subtree", node)


func _configure_control(node: Node) -> void:
	if node is ScrollContainer:
		var scroll := node as ScrollContainer
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		return

	if node is OptionButton:
		var option := node as OptionButton
		option.fit_to_longest_item = false
		option.clip_text = true
		option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		return

	if node is Button:
		var button := node as Button
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		return

	if node is Label:
		var label := node as Label
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if label.tooltip_text.is_empty() and not label.text.is_empty():
			label.tooltip_text = label.text
		return

	if node is LineEdit:
		var line_edit := node as LineEdit
		line_edit.expand_to_text_length = false
