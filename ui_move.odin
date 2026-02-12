package main

import clay "clay-odin"
import "core:strings"

// Define missing colors here or map to existing
COLOR_MOVE_BG :: clay.Color{70, 130, 180, 255} // Steel Blue
COLOR_MOVE_HOVER :: clay.Color{100, 149, 237, 255} // Cornflower Blue
COLOR_CANCEL_BG :: clay.Color{178, 34, 34, 255} // Firebrick

// Helper to render Move button
render_move_button :: proc(cmd: ^SavedCommand) {
	if clay.UI()(
	{
		id = clay.ID("MoveBtn", cmd.id),
		layout = {padding = {5, 5, 2, 2}},
		backgroundColor = clay.PointerOver(clay.ID("MoveBtn", cmd.id)) ? COLOR_MOVE_HOVER : COLOR_MOVE_BG,
		cornerRadius = {4, 4, 4, 4},
	},
	) {
		clay.Text(
			"Move",
			clay.TextConfig({textColor = COLOR_TEXT, fontSize = 14, fontId = FONT_ID_BODY_14}),
		)
	}
}

// Helper to render Move Cancel button (at top of sidebar?)
render_move_cancel_button :: proc() {
	if clay.UI()(
	{
		id = clay.ID("MoveCancelBtn"),
		layout = {
			padding = {10, 10, 5, 5},
			sizing = {width = clay.SizingGrow({})},
			childAlignment = {x = .Center},
		},
		backgroundColor = COLOR_CANCEL_BG, // Reddish to indicate cancel/stop
		cornerRadius = {4, 4, 4, 4},
	},
	) {
		clay.Text(
			"Cancel Move",
			clay.TextConfig({textColor = COLOR_TEXT, fontSize = 14, fontId = FONT_ID_BODY_14}),
		)
	}
}

// Render root as drop target
render_root_drop_target :: proc() {
	if _, ok := app_state.moving_cmd_id.?; ok {
		if clay.UI()(
		{
			id = clay.ID("DropRoot"),
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(30)},
				childAlignment = {x = .Center, y = .Center},
				padding = {0, 0, 5, 5},
			},
			backgroundColor = clay.PointerOver(clay.ID("DropRoot")) ? COLOR_MOVE_HOVER : COLOR_PANEL, // Use COLOR_PANEL from main
		},
		) {
			clay.Text(
				"Move to Root",
				clay.TextConfig({textColor = COLOR_TEXT, fontSize = 14, fontId = FONT_ID_BODY_14}),
			)
		}
	}
}
