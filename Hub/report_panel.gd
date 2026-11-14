class_name ReportPanel
extends HubPanel

# Shown once when the player gets back to the station: what came back, what it cost.
# Reads GameState.last_report, then clears it.

var _report: Dictionary


func _init(report: Dictionary) -> void:
	super("BACK ABOARD" if report.get("outcome") == "docked" else "SHIP LOST")
	_report = report


func _build() -> void:
	body.add_child(HubStyle.label(_report.get("field", ""), 16, HubStyle.DIM))

	if _report.get("outcome") == "docked":
		var ore: Dictionary = _report.get("ore", {})
		var any := false

		for ore_id in CellMaterials.ORES:
			var units: float = ore.get(ore_id, 0.0)

			if units >= 0.5:
				any = true
				var value: int = GameState.get_sale_quote(ore_id, units).revenue
				body.add_child(HubStyle.label("%s   %d u   about %s" % [CellMaterials.get_material(ore_id).display_name, roundi(units), HubStyle.format_credits(value)], 17))

		if not any:
			body.add_child(HubStyle.label("Empty hold.", 17))

		body.add_child(HubStyle.label("Ore goes to your bay at the station. Sell it at the exchange.", 14, HubStyle.DIM))

		var hull: float = _report.get("hull", 1.0)
		var hull_color := HubStyle.BAD if hull < GameState.ECONOMY.repair_reminder_threshold else HubStyle.TEXT
		body.add_child(HubStyle.label("Hull %d%%" % roundi(hull * 100.0), 17, hull_color))
	else:
		body.add_child(HubStyle.label("The cargo is gone.", 17, HubStyle.BAD))
		var payout: int = _report.get("payout", 0)
		body.add_child(HubStyle.label("Insurance paid %s." % HubStyle.format_credits(payout) if payout > 0 else "No insurance payout.", 17))
		body.add_child(HubStyle.label("%s lost with its modules." % _report.get("ship", "The ship"), 15))

		if _report.get("replaced", false):
			body.add_child(HubStyle.label("It was your last ship: the Union lends you a Bucket.", 14, HubStyle.DIM))

	_build_contracts()
	body.add_child(HubStyle.label("Fees this run: %s" % HubStyle.format_credits(_report.get("fees", 0)), 17))

	var ok := HubStyle.button("OK", 18)
	ok.pressed.connect(close_panel)
	body.add_child(ok)


# What the guild paid, what was handed in, and the rush deliveries that ran out.
func _build_contracts() -> void:
	var contracts: Dictionary = _report.get("contracts", {})
	var delivered: Dictionary = _report.get("delivered", {})

	for ore_id in delivered:
		if delivered[ore_id] >= 0.5:
			body.add_child(HubStyle.label("Handed to the guild: %d u %s" % [roundi(delivered[ore_id]), CellMaterials.get_material(ore_id).display_name], 15))

	for paid in contracts.get("paid", []):
		body.add_child(HubStyle.label("Guild paid %s: %s" % [HubStyle.format_credits(paid.reward), paid.title], 17, HubStyle.GOOD))

	for title in contracts.get("expired", []):
		body.add_child(HubStyle.label("%s ran out." % title, 15, HubStyle.BAD))
