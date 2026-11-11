class_name ServicePanel
extends HubPanel

# The station services that aren't built yet: placeholders with a line of text.

const TEXTS := {
	&"shipyard": "Closed for refit. The Crab is on its way.",
	&"guild": "Contracts and mining licences open soon.",
}

var _service: StringName


func _init(service: StringName, title: String) -> void:
	super(title)
	_service = service


func _build() -> void:
	var text := HubStyle.label(TEXTS.get(_service, ""), 16)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(text)
