class_name DtlTimelineParser
extends RefCounted

## DtlTimelineParser: Единый облегчённый парсер .dtl таймлайнов Dialogic 2
## для EventScene и MidBattleDialogueOverlay (T-13).

static func resolve_timeline_path(path: String) -> String:
	if path == "":
		return ""
	if FileAccess.file_exists(path):
		return path
	var cand: String = path
	if not cand.begins_with("res://"):
		cand = "res://data/dialogues/" + cand
	if not cand.ends_with(".dtl"):
		cand += ".dtl"
	if FileAccess.file_exists(cand):
		return cand
	return ""

static func _extract_quoted_value(line: String) -> String:
	var q1: int = line.find("\"")
	var q2: int = line.rfind("\"")
	if q1 != -1 and q2 > q1:
		return line.substr(q1 + 1, q2 - q1 - 1)
	return ""

static func parse_timeline(
	path: String,
	initial_image: String = "",
	infer_choice_signals: bool = true
) -> Dictionary:
	var lines: Array[Dictionary] = []
	var choices: Array[Dictionary] = []
	var full_path: String = resolve_timeline_path(path)
	if full_path == "":
		return {
			"found": false,
			"resolved_path": "",
			"lines": lines,
			"choices": choices
		}

	var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		return {
			"found": false,
			"resolved_path": full_path,
			"lines": lines,
			"choices": choices
		}
	var raw_lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	var current_choice: Dictionary = {}
	var current_image: String = initial_image
	var current_sfx: String = ""
	var current_video: String = ""

	for raw: String in raw_lines:
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue

		if line.begins_with("[image"):
			var img_val: String = _extract_quoted_value(line)
			if img_val != "":
				current_image = img_val
		elif line.begins_with("[video"):
			var vid_val: String = _extract_quoted_value(line)
			if vid_val != "":
				current_video = vid_val
		elif line.begins_with("[sound") or line.begins_with("[audio") or line.begins_with("[sfx"):
			var sfx_val: String = _extract_quoted_value(line)
			if sfx_val != "":
				current_sfx = sfx_val
		elif line.begins_with("- "):
			var lbl: String = line.substr(2).strip_edges()
			var def_sig: String = ""
			if infer_choice_signals:
				def_sig = "safe_scrap"
				if lbl.find("Yes") != -1 or lbl.find("Да") != -1:
					def_sig = "boomer_true"
				elif lbl.find("No") != -1 or lbl.find("Нет") != -1:
					def_sig = "boomer_false"
			current_choice = {
				"label": lbl,
				"signal": def_sig,
				"branch_lines": []
			}
			choices.append(current_choice)
		elif line.begins_with("[signal"):
			var sig_val: String = _extract_quoted_value(line)
			if sig_val != "" and not current_choice.is_empty():
				current_choice["signal"] = sig_val
		elif not line.begins_with("[") and line.find(":") != -1:
			var colon_idx: int = line.find(":")
			var head: String = line.substr(0, colon_idx).strip_edges()
			var body: String = line.substr(colon_idx + 1).strip_edges()
			var char_id: String = "felix"
			var mood: String = "normal"
			var p_open: int = head.find("(")
			var p_close: int = head.find(")")
			if p_open != -1 and p_close > p_open:
				char_id = head.substr(0, p_open).strip_edges().to_lower()
				mood = head.substr(p_open + 1, p_close - p_open - 1).strip_edges().to_lower()
			else:
				char_id = head.to_lower()

			var parsed_item: Dictionary = {
				"char": char_id,
				"mood": mood,
				"text": body,
				"image": current_image,
				"sfx": current_sfx,
				"video": current_video,
				"video_played": false
			}
			current_sfx = ""
			current_video = ""

			if not choices.is_empty() and (raw.begins_with("\t") or raw.begins_with("  ")):
				var bl: Array = current_choice.get("branch_lines", []) as Array
				bl.append(parsed_item)
				current_choice["branch_lines"] = bl
			else:
				lines.append(parsed_item)

	return {
		"found": true,
		"resolved_path": full_path,
		"lines": lines,
		"choices": choices
	}
