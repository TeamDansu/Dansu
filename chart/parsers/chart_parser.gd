@abstract
extends RefCounted
class_name ChartParser

@abstract
func parse(_file: FileAccess, _chart: Chart) -> bool
