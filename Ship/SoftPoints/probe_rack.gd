class_name ProbeRack
extends ItemRack

# Launches survey probes. They drift with the momentum they leave with, and ping the rocks around
# them, revealing their ore (see SurveyProbe). A probe taken back is recharged.


func _init() -> void:
	footprint = Rect2(0, -10, 9, 20)
	capacity = 2
	item_mass = 1.0
	launch_speed = 35.0
	item_color = Color(0.35, 0.85, 1.0)


func _make_item() -> SpaceProp:
	return SurveyProbe.new()


func _is_my_item(prop: SpaceProp) -> bool:
	return prop is SurveyProbe


func _on_item_launched(item: SpaceProp) -> void:
	say("Probe P%d launched" % (item as SurveyProbe).number)
