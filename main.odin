package main

import "base:runtime"
import clay "clay-odin"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "vendor:raylib"

// Colors
COLOR_BG :: clay.Color{30, 30, 35, 255}
COLOR_SIDEBAR :: clay.Color{40, 42, 48, 255}
COLOR_PANEL :: clay.Color{45, 47, 53, 255}
COLOR_INPUT :: clay.Color{55, 58, 65, 255}
COLOR_INPUT_FOCUS :: clay.Color{65, 68, 75, 255}
COLOR_TEXT :: clay.Color{230, 230, 235, 255}
COLOR_TEXT_DIM :: clay.Color{150, 150, 160, 255}
COLOR_ACCENT :: clay.Color{100, 140, 230, 255}
COLOR_ACCENT_HOVER :: clay.Color{120, 160, 250, 255}
COLOR_SUCCESS :: clay.Color{80, 180, 120, 255}
COLOR_WARNING :: clay.Color{220, 180, 80, 255}
COLOR_ERROR :: clay.Color{220, 90, 90, 255}
COLOR_ITEM_HOVER :: clay.Color{55, 58, 65, 255}
COLOR_PANEL_HOVER :: clay.Color{60, 62, 68, 255}
COLOR_MOVE_HOVER :: clay.Color{100, 149, 237, 255}


// Syntax highlighting colors for curl commands
COLOR_SYN_COMMAND :: clay.Color{120, 120, 130, 255} // dim gray for "curl"
COLOR_SYN_FLAG :: clay.Color{100, 160, 240, 255} // blue for flags
COLOR_SYN_METHOD :: clay.Color{230, 180, 80, 255} // orange for HTTP methods
COLOR_SYN_URL :: clay.Color{100, 200, 150, 255} // green for URLs
COLOR_SYN_HEADER :: clay.Color{180, 140, 220, 255} // purple for header names
COLOR_SYN_STRING :: clay.Color{140, 200, 200, 255} // cyan for strings
COLOR_SYN_JSON :: clay.Color{220, 200, 100, 255} // yellow for JSON braces
COLOR_SYN_ERROR :: clay.Color{220, 80, 80, 255} // red for errors

SIDEBAR_WIDTH :: 280


windowWidth: i32 = 1024
windowHeight: i32 = 768

FONT_ID_BODY_16 :: 0
FONT_ID_BODY_36 :: 5
FONT_ID_BODY_30 :: 6
FONT_ID_BODY_28 :: 7
FONT_ID_BODY_24 :: 8
FONT_ID_BODY_14 :: 9
FONT_ID_BODY_12 :: 10
FONT_ID_BODY_18 :: 11
FONT_ID_BODY_20 :: 12

g_font: raylib.Font


// App state
app_state: AppState

// Input focus tracking
FocusedInput :: enum {
	None,
	Search,
	CurlInput,
	NameInput,
}

focused_input: FocusedInput = .None

clay_color_to_rl_color :: proc(color: clay.Color) -> raylib.Color {
	return {u8(color.r), u8(color.g), u8(color.b), u8(color.a)}
}

// raylib_fonts removed


draw_arc :: proc(
	x, y: f32,
	inner_rad, outer_rad: f32,
	start_angle, end_angle: f32,
	color: clay.Color,
) {
	raylib.DrawRing(
		{math.round(x), math.round(y)},
		math.round(inner_rad),
		outer_rad,
		start_angle,
		end_angle,
		10,
		clay_color_to_rl_color(color),
	)
}

draw_rect :: proc(x, y, w, h: f32, color: clay.Color) {
	raylib.DrawRectangle(
		i32(math.round(x)),
		i32(math.round(y)),
		i32(math.round(w)),
		i32(math.round(h)),
		clay_color_to_rl_color(color),
	)
}

draw_rect_rounded :: proc(x, y, w, h: f32, radius: f32, color: clay.Color) {
	raylib.DrawRectangleRounded({x, y, w, h}, radius, 8, clay_color_to_rl_color(color))
}

measure_text :: proc "c" (
	text: clay.StringSlice,
	config: ^clay.TextElementConfig,
	userData: rawptr,
) -> clay.Dimensions {
	// Convert text to cstring for Raylib
	// Note: We need a temporary allocator here, but we are in a "c" proc called by Clay.
	// Clay usually runs within the main loop where temp_allocator is valid.
	context = runtime.default_context()

	text_str := string(text.chars[:text.length])
	cstr_text := strings.clone_to_cstring(text_str, context.temp_allocator)

	vec2 := raylib.MeasureTextEx(
		g_font,
		cstr_text,
		f32(config.fontSize),
		f32(config.letterSpacing),
	)

	return {width = vec2.x, height = vec2.y}
}

error_handler :: proc "c" (err_data: clay.ErrorData) {
	context = runtime.default_context()
	fmt.printfln("%s", err_data.errorText)
}

// Handle keyboard input for text fields with cursor and selection support
handle_text_input :: proc(
	buffer: []u8,
	length: ^int,
	max_len: int,
	cursor: ^int,
	sel_anchor: ^Maybe(int),
) {
	// Clamp cursor to valid range
	cursor^ = clamp(cursor^, 0, length^)

	shift_held := raylib.IsKeyDown(.LEFT_SHIFT) || raylib.IsKeyDown(.RIGHT_SHIFT)
	ctrl_held :=
		raylib.IsKeyDown(.LEFT_CONTROL) ||
		raylib.IsKeyDown(.RIGHT_CONTROL) ||
		raylib.IsKeyDown(.LEFT_SUPER) ||
		raylib.IsKeyDown(.RIGHT_SUPER) // Mac Command key

	// Helper to get selection range (sorted)
	get_selection :: proc(
		cursor: int,
		anchor: Maybe(int),
	) -> (
		start: int,
		end: int,
		has_sel: bool,
	) {
		if anchor_pos, ok := anchor.?; ok {
			if anchor_pos < cursor {
				return anchor_pos, cursor, true
			} else if anchor_pos > cursor {
				return cursor, anchor_pos, true
			}
		}
		return 0, 0, false
	}

	// Helper to delete selection
	delete_selection :: proc(
		buffer: []u8,
		length: ^int,
		cursor: ^int,
		sel_anchor: ^Maybe(int),
	) -> bool {
		sel_start, sel_end, has_sel := get_selection(cursor^, sel_anchor^)
		if !has_sel {return false}

		// Delete selected text by shifting
		chars_to_delete := sel_end - sel_start
		for i := sel_start; i < length^ - chars_to_delete; i += 1 {
			buffer[i] = buffer[i + chars_to_delete]
		}
		for i := length^ - chars_to_delete; i < length^; i += 1 {
			buffer[i] = 0
		}
		length^ -= chars_to_delete
		cursor^ = sel_start
		sel_anchor^ = nil
		return true
	}

	// Handle Ctrl+A to select all
	if ctrl_held && raylib.IsKeyPressed(.A) {
		sel_anchor^ = 0
		cursor^ = length^
		return
	}

	// Handle Ctrl+V paste (delete selection first)
	if ctrl_held && raylib.IsKeyPressed(.V) {
		delete_selection(buffer, length, cursor, sel_anchor)
		clipboard := raylib.GetClipboardText()
		if clipboard != nil {
			clipboard_str := string(clipboard)
			for c in clipboard_str {
				if length^ < max_len - 1 && c >= 32 && c < 127 {
					// Shift characters after cursor to the right
					for i := length^; i > cursor^; i -= 1 {
						buffer[i] = buffer[i - 1]
					}
					buffer[cursor^] = u8(c)
					length^ += 1
					cursor^ += 1
				}
			}
		}
		return
	}

	// Handle Ctrl+C copy
	if ctrl_held && raylib.IsKeyPressed(.C) {
		sel_start, sel_end, has_sel := get_selection(cursor^, sel_anchor^)
		if has_sel {
			selected_text := string(buffer[sel_start:sel_end])
			cstr := strings.clone_to_cstring(selected_text)
			defer delete(cstr)
			raylib.SetClipboardText(cstr)
		}
		return
	}

	// Handle Ctrl+X cut
	if ctrl_held && raylib.IsKeyPressed(.X) {
		sel_start, sel_end, has_sel := get_selection(cursor^, sel_anchor^)
		if has_sel {
			selected_text := string(buffer[sel_start:sel_end])
			cstr := strings.clone_to_cstring(selected_text)
			defer delete(cstr)
			raylib.SetClipboardText(cstr)
			delete_selection(buffer, length, cursor, sel_anchor)
		}
		return
	}

	// Handle arrow keys (with shift for selection)
	if raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressedRepeat(.LEFT) {
		if shift_held {
			// Start or extend selection
			if sel_anchor^ == nil {
				sel_anchor^ = cursor^
			}
		} else {
			// Clear selection, maybe jump to selection edge
			if sel_start, _, has_sel := get_selection(cursor^, sel_anchor^); has_sel {
				cursor^ = sel_start
				sel_anchor^ = nil
				return
			}
			sel_anchor^ = nil
		}
		if cursor^ > 0 {
			cursor^ -= 1
		}
	}
	if raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressedRepeat(.RIGHT) {
		if shift_held {
			if sel_anchor^ == nil {
				sel_anchor^ = cursor^
			}
		} else {
			if _, sel_end, has_sel := get_selection(cursor^, sel_anchor^); has_sel {
				cursor^ = sel_end
				sel_anchor^ = nil
				return
			}
			sel_anchor^ = nil
		}
		if cursor^ < length^ {
			cursor^ += 1
		}
	}

	// Handle Home/End (with shift for selection)
	if raylib.IsKeyPressed(.HOME) {
		if shift_held {
			if sel_anchor^ == nil {
				sel_anchor^ = cursor^
			}
		} else {
			sel_anchor^ = nil
		}
		cursor^ = 0
	}
	if raylib.IsKeyPressed(.END) {
		if shift_held {
			if sel_anchor^ == nil {
				sel_anchor^ = cursor^
			}
		} else {
			sel_anchor^ = nil
		}
		cursor^ = length^
	}

	// Handle character input - replace selection or insert at cursor
	for {
		char := raylib.GetCharPressed()
		if char == 0 {break}
		if char >= 32 && char < 127 {
			// Delete selection first if any
			delete_selection(buffer, length, cursor, sel_anchor)

			if length^ < max_len - 1 {
				// Shift characters after cursor to the right
				for i := length^; i > cursor^; i -= 1 {
					buffer[i] = buffer[i - 1]
				}
				buffer[cursor^] = u8(char)
				length^ += 1
				cursor^ += 1
				sel_anchor^ = nil // Clear anchor so we don't accidentally select the new char
			}
		}
	}

	// Handle backspace - delete selection or character before cursor
	if raylib.IsKeyPressed(.BACKSPACE) || raylib.IsKeyPressedRepeat(.BACKSPACE) {
		if !delete_selection(buffer, length, cursor, sel_anchor) {
			if cursor^ > 0 {
				// Shift characters after cursor to the left
				for i := cursor^ - 1; i < length^ - 1; i += 1 {
					buffer[i] = buffer[i + 1]
				}
				buffer[length^ - 1] = 0
				length^ -= 1
				cursor^ -= 1
			}
		}
	}

	// Handle delete - delete selection or character at cursor
	if raylib.IsKeyPressed(.DELETE) || raylib.IsKeyPressedRepeat(.DELETE) {
		if !delete_selection(buffer, length, cursor, sel_anchor) {
			if cursor^ < length^ {
				// Shift characters after cursor to the left
				for i := cursor^; i < length^ - 1; i += 1 {
					buffer[i] = buffer[i + 1]
				}
				buffer[length^ - 1] = 0
				length^ -= 1
			}
		}
	}
}

// Get string from buffer
buffer_to_string :: proc(buffer: []u8, length: int) -> string {
	if length <= 0 {return ""}
	return string(buffer[:length])
}

// Filter commands by search text (recursive helper)
search_recursive :: proc(
	commands: []SavedCommand,
	search_lower: string,
	result: ^[dynamic]^SavedCommand,
) {
	for &cmd in commands {
		cmd_name_lower := strings.to_lower(cmd.name, context.temp_allocator)
		if strings.contains(cmd_name_lower, search_lower) {
			append(result, &cmd)
		}

		if len(cmd.children) > 0 {
			search_recursive(cmd.children[:], search_lower, result)
		}
	}
}

// Filter commands by search text
get_filtered_commands :: proc() -> [dynamic]^SavedCommand {
	result := make([dynamic]^SavedCommand, context.temp_allocator)
	search := buffer_to_string(app_state.search_text[:], app_state.search_len)

	if len(search) == 0 {
		return result // Should not be used when search is empty ideally
	}

	search_lower := strings.to_lower(search, context.temp_allocator)
	search_recursive(app_state.commands[:], search_lower, &result)

	return result
}

// Get color for a token type (for syntax highlighting)
get_token_color :: proc(token_type: TokenType, has_error: bool) -> clay.Color {
	if has_error {
		return COLOR_SYN_ERROR
	}

	switch token_type {
	case .Command:
		return COLOR_SYN_COMMAND
	case .Flag:
		return COLOR_SYN_FLAG
	case .Method:
		return COLOR_SYN_METHOD
	case .URL:
		return COLOR_SYN_URL
	case .HeaderName:
		return COLOR_SYN_HEADER
	case .HeaderValue:
		return COLOR_TEXT_DIM
	case .String:
		return COLOR_SYN_STRING
	case .JsonBrace:
		return COLOR_SYN_JSON
	case .Data:
		return COLOR_TEXT
	case .Whitespace:
		return COLOR_TEXT
	case .Backslash:
		return COLOR_SYN_FLAG // Highlight backslash like a flag? or Operator color
	case .Newline:
		return COLOR_TEXT
	case .Error:
		return COLOR_SYN_ERROR
	}
	return COLOR_TEXT
}

COLOR_FOLDER :: clay.Color{60, 62, 68, 255}

// Recursive helper to render command nodes
render_command_node :: proc(commands: ^[dynamic]SavedCommand, cmd_idx: int, depth: int) {
	cmd := &commands[cmd_idx]
	is_selected := app_state.selected_id == cmd.id
	is_editing := app_state.editing_id == cmd.id

	// Indentation
	padding_left: u16 = 10 + (u16(depth) * 16)

	if cmd.type == .Folder {
		// Folder rendering
		bg_color := is_selected ? COLOR_ACCENT : COLOR_FOLDER
		if app_state.is_dragging {
			if dragging_id, ok := app_state.dragging_id.?; ok && dragging_id != cmd.id {
				if clay.PointerOver(clay.ID("CmdItem", cmd.id)) {
					bg_color = COLOR_MOVE_HOVER
				}
			}
		}

		if clay.UI()(
		{
			id = clay.ID("CmdItem", cmd.id),
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(36)},
				padding = {padding_left, 10, 8, 8},
				childAlignment = {y = .Center},
				childGap = 8,
			},
			backgroundColor = bg_color,
			cornerRadius = {4, 4, 4, 4},
		},
		) {
			// Expand/Collapse toggle (caret)
			// Text removed, will draw custom vector icon in main loop
			if clay.UI()(
			{
				id = clay.ID("FolderToggle", cmd.id),
				layout = {
					sizing = {width = clay.SizingFixed(24), height = clay.SizingFixed(24)},
					childAlignment = {x = .Center, y = .Center},
				},
			},
			) {
				// Empty - custom draw
			}

			// Folder Name
			if is_editing {
				if clay.UI()(
				{
					id = clay.ID("CmdName", cmd.id),
					layout = {
						sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
						childAlignment = {y = .Center},
					},
					clip = {horizontal = true, childOffset = {-app_state.name_input_scroll_x, 0}},
				},
				) {
					name_text := buffer_to_string(
						app_state.name_input[:],
						app_state.name_input_len,
					)
					if app_state.name_input_len > 0 {
						clay.TextDynamic(
							name_text,
							clay.TextConfig(
								{textColor = COLOR_TEXT, fontSize = 18, fontId = FONT_ID_BODY_18},
							),
						)
					} else {
						clay.Text(
							"Folder name...",
							clay.TextConfig(
								{
									textColor = COLOR_TEXT_DIM,
									fontSize = 18,
									fontId = FONT_ID_BODY_18,
								},
							),
						)
					}
				}
			} else {
				// Render name - wrapped in clipped container
				if clay.UI()(
				{
					id = clay.ID("CmdName", cmd.id),
					layout = {
						sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
						childAlignment = {y = .Center},
					},
					clip = {horizontal = true},
				},
				) {
					clay.TextDynamic(
						cmd.name,
						clay.TextConfig(
							{textColor = COLOR_TEXT, fontSize = 18, fontId = FONT_ID_BODY_18},
						),
					)
				}
			}

			// Edit/Delete buttons (same as commands)
			if is_selected && !is_editing {
				render_command_actions(cmd)
			}

			// Save/Move actions
			if is_editing {
				render_save_action(cmd)
			}

			// Drag Mode: Highlight as drop target (implementation pending)
			// Will be added when drag logic is implemented
		}


		// Render children if expanded
		if cmd.expanded {
			for child_idx := 0; child_idx < len(cmd.children); child_idx += 1 {
				render_command_node(&cmd.children, child_idx, depth + 1)
			}
		}

	} else {
		// Request rendering
		item_bg := is_selected ? COLOR_ACCENT : COLOR_ITEM_HOVER

		if clay.UI()(
		{
			id = clay.ID("CmdItem", cmd.id),
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(44)},
				padding = {padding_left, 10, 8, 8},
				childAlignment = {y = .Center},
			},
			backgroundColor = item_bg,
			cornerRadius = {4, 4, 4, 4},
		},
		) {
			// Command name or duplicate of editing logic
			if is_editing {
				if clay.UI()(
				{
					id = clay.ID("CmdName", cmd.id),
					layout = {
						sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
						childAlignment = {y = .Center},
					},
					clip = {horizontal = true, childOffset = {-app_state.name_input_scroll_x, 0}},
				},
				) {
					name_text := buffer_to_string(
						app_state.name_input[:],
						app_state.name_input_len,
					)
					if app_state.name_input_len > 0 {
						clay.TextDynamic(
							name_text,
							clay.TextConfig(
								{textColor = COLOR_TEXT, fontSize = 18, fontId = FONT_ID_BODY_18},
							),
						)
					} else {
						clay.Text(
							"Enter name...",
							clay.TextConfig(
								{
									textColor = COLOR_TEXT_DIM,
									fontSize = 18,
									fontId = FONT_ID_BODY_18,
								},
							),
						)
					}
				}
			} else {
				if clay.UI()(
				{
					id = clay.ID("CmdName", cmd.id),
					layout = {
						sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
						childAlignment = {y = .Center},
					},
					clip = {horizontal = true},
				},
				) {
					clay.TextDynamic(
						cmd.name,
						clay.TextConfig(
							{textColor = COLOR_TEXT, fontSize = 18, fontId = FONT_ID_BODY_18},
						),
					)
				}
			}

			// Show buttons when selected
			if is_selected && !is_editing {
				render_command_actions(cmd)
			}

			// Show Save button when editing
			if is_editing {
				render_save_action(cmd)
			}
		}
	}
}

// Helper to render Edit/Del buttons
render_command_actions :: proc(cmd: ^SavedCommand) {
	// Edit button
	if clay.UI()(
	{
		id = clay.ID("EditBtn", cmd.id),
		layout = {
			sizing = {width = clay.SizingFixed(60), height = clay.SizingFixed(28)},
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = COLOR_WARNING,
		cornerRadius = {4, 4, 4, 4},
	},
	) {
		clay.Text(
			"Edit",
			clay.TextConfig({textColor = COLOR_BG, fontSize = 14, fontId = FONT_ID_BODY_14}),
		)
	}

	// Delete button
	if clay.UI()(
	{
		id = clay.ID("DelBtn", cmd.id),
		layout = {
			sizing = {width = clay.SizingFixed(60), height = clay.SizingFixed(28)},
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = COLOR_ERROR,
		cornerRadius = {4, 4, 4, 4},
	},
	) {
		clay.Text(
			"Del",
			clay.TextConfig({textColor = COLOR_TEXT, fontSize = 14, fontId = FONT_ID_BODY_14}),
		)
	}
}

render_save_action :: proc(cmd: ^SavedCommand) {
	if clay.UI()(
	{
		id = clay.ID("SaveNameBtn", cmd.id),
		layout = {
			sizing = {width = clay.SizingFixed(60), height = clay.SizingFixed(28)},
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = COLOR_SUCCESS,
		cornerRadius = {4, 4, 4, 4},
	},
	) {
		clay.Text(
			"Save",
			clay.TextConfig({textColor = COLOR_TEXT, fontSize = 14, fontId = FONT_ID_BODY_14}),
		)
	}
}


// Create the sidebar with search and command list
sidebar_component :: proc() {
	if clay.UI()(
	{
		id = clay.ID("Sidebar"),
		layout = {
			layoutDirection = .TopToBottom,
			sizing = {width = clay.SizingFixed(SIDEBAR_WIDTH), height = clay.SizingGrow({})},
			padding = {12, 12, 12, 12},
			childGap = 12,
		},
		backgroundColor = COLOR_SIDEBAR,
	},
	) {
		// Title
		clay.Text(
			"Liteman",
			clay.TextConfig({textColor = COLOR_TEXT, fontSize = 28, fontId = FONT_ID_BODY_28}),
		)

		// New Buttons Row
		if clay.UI()(
		{
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(32)},
				childGap = 8,
			},
		},
		) {
			// New Request Button
			if clay.UI()(
			{
				id = clay.ID("NewRequestBtn"),
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					childAlignment = {x = .Center, y = .Center},
				},
				backgroundColor = clay.PointerOver(clay.ID("NewRequestBtn")) ? COLOR_ACCENT_HOVER : COLOR_ACCENT,
				cornerRadius = {4, 4, 4, 4},
			},
			) {
				clay.Text(
					"New Req",
					clay.TextConfig(
						{textColor = COLOR_TEXT, fontSize = 14, fontId = FONT_ID_BODY_14},
					),
				)
			}

			// New Folder Button
			if clay.UI()(
			{
				id = clay.ID("NewFolderBtn"),
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					childAlignment = {x = .Center, y = .Center},
				},
				backgroundColor = clay.PointerOver(clay.ID("NewFolderBtn")) ? COLOR_PANEL_HOVER : COLOR_PANEL,
				cornerRadius = {4, 4, 4, 4},
			},
			) {
				clay.Text(
					"New Folder",
					clay.TextConfig(
						{textColor = COLOR_TEXT, fontSize = 14, fontId = FONT_ID_BODY_14},
					),
				)
			}
		}
		// Search input
		search_bg := focused_input == .Search ? COLOR_INPUT_FOCUS : COLOR_INPUT
		if clay.UI()(
		{
			id = clay.ID("SearchBox"),
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(36)},
				padding = {10, 10, 8, 8},
			},
			backgroundColor = search_bg,
			cornerRadius = {4, 4, 4, 4},
		},
		) {
			search_text := buffer_to_string(app_state.search_text[:], app_state.search_len)
			if app_state.search_len > 0 {
				clay.TextDynamic(
					search_text,
					clay.TextConfig(
						{textColor = COLOR_TEXT, fontSize = 18, fontId = FONT_ID_BODY_18},
					),
				)
			} else {
				clay.Text(
					"Search commands...",
					clay.TextConfig(
						{textColor = COLOR_TEXT_DIM, fontSize = 18, fontId = FONT_ID_BODY_18},
					),
				)
			}
		}

		// Commands list with scrollbar
		// Get scroll data for this container
		sidebar_scroll_id := clay.ID("CommandsList")
		sidebar_scroll := clay.GetScrollContainerData(sidebar_scroll_id)
		sidebar_scroll_offset: clay.Vector2 = {0, 0}
		if sidebar_scroll.found && sidebar_scroll.scrollPosition != nil {
			sidebar_scroll_offset = sidebar_scroll.scrollPosition^
		}

		// Horizontal wrapper for list + scrollbar
		if clay.UI()(
		{
			layout = {
				layoutDirection = .LeftToRight,
				sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			},
		},
		) {
			// Scrollable command list
			if clay.UI()(
			{
				id = sidebar_scroll_id,
				layout = {
					layoutDirection = .TopToBottom,
					sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					childGap = 4,
				},
				clip = {vertical = true, childOffset = sidebar_scroll_offset},
			},
			) {
				// Use recursive rendering for the command hierarchy
				// Note: filtering is simpler if we just show everything for now when not searching
				// Or implementing filter logic inside recursive function?

				// For now, if searching, we might want to flatten or filter.
				// Let's assume we render the tree.
				// If search is active, we might need a different view, but for MVP let's implement the tree.

				// Warning: get_filtered_commands() returned a flat list of pointers.
				// We need to change how we iterate.

				// Check if search is active
				is_searching := app_state.search_len > 0

				if is_searching {
					// Fallback to flat filtered list (assumes we updated get_filtered_commands to handle types)
					// We need to update get_filtered_commands to be recursive-aware or return a flat list of matches.
					// Implementation of that is pending in next steps.
					// For now, let's just render the root level recursively.

					// Actually, the previous implementation of get_filtered_commands returns pointers.
					// Let's rely on that for search for now, but we need to update it to traverse children.
					// And we need to update the rendering loop here to handle pointers vs value iteration.

					filtered_cmds := get_filtered_commands()
					for cmd_ptr, i in filtered_cmds {
						// Render as flat list if searching (ignoring depth/folder structure for simplicity in search results)
						// Or we can try to find their parents... simpler to just list matches.

						// Using a simplified render logic for search results?
						// We can just reuse the "request" style rendering.

						// FIX: We need to handle dereferencing properly
						cmd := cmd_ptr // It's a pointer

						is_selected := app_state.selected_id == cmd.id
						item_bg := is_selected ? COLOR_ACCENT : COLOR_ITEM_HOVER

						if clay.UI()(
						{
							id = clay.ID("CmdItem", cmd.id),
							layout = {
								sizing = {
									width = clay.SizingGrow({}),
									height = clay.SizingFixed(44),
								},
								padding = {10, 10, 8, 8},
								childAlignment = {y = .Center},
							},
							backgroundColor = item_bg,
							cornerRadius = {4, 4, 4, 4},
						},
						) {
							clay.TextDynamic(
								cmd.name,
								clay.TextConfig(
									{
										textColor = COLOR_TEXT,
										fontSize = 18,
										fontId = FONT_ID_BODY_18,
									},
								),
							)

							// Allow selection
							if is_selected {
								render_command_actions(cmd)
							}
						}
					}

				} else {
					// Standard recursive tree view
					for i := 0; i < len(app_state.commands); i += 1 {
						render_command_node(&app_state.commands, i, 0)
					}
				}
			}

			// Sidebar scrollbar (only show if content overflows)
			if sidebar_scroll.found &&
			   sidebar_scroll.contentDimensions.height >
				   sidebar_scroll.scrollContainerDimensions.height {
				// Calculate scrollbar metrics
				container_height := sidebar_scroll.scrollContainerDimensions.height
				content_height := sidebar_scroll.contentDimensions.height
				scroll_y := -sidebar_scroll_offset.y

				// Thumb height proportional to visible area
				thumb_height := max(30, container_height * (container_height / content_height))
				// Thumb position proportional to scroll
				scrollable_range := content_height - container_height
				thumb_offset := (scroll_y / scrollable_range) * (container_height - thumb_height)
				thumb_offset = clamp(thumb_offset, 0, container_height - thumb_height)

				// Scrollbar track
				if clay.UI()(
				{
					id = clay.ID("SidebarScrollbarTrack"),
					layout = {
						sizing = {width = clay.SizingFixed(6), height = clay.SizingGrow({})},
						padding = {0, 0, u16(thumb_offset), 0},
					},
					backgroundColor = {50, 50, 55, 255},
					cornerRadius = {3, 3, 3, 3},
				},
				) {
					// Scrollbar thumb
					if clay.UI()(
					{
						id = clay.ID("SidebarScrollbarThumb"),
						layout = {
							sizing = {
								width = clay.SizingFixed(6),
								height = clay.SizingFixed(thumb_height),
							},
						},
						backgroundColor = {100, 110, 130, 255},
						cornerRadius = {3, 3, 3, 3},
					},
					) {}
				}
			}
		}
	}
}

// Get status color based on code
get_status_color :: proc(code: int) -> clay.Color {
	if code >= 200 && code < 300 {return COLOR_SUCCESS}
	if code >= 300 && code < 400 {return COLOR_WARNING}
	return COLOR_ERROR
}

// Main content component (Response view)
main_content_component :: proc() {
	if clay.UI()(
	{
		id = clay.ID("MainContent"),
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			layoutDirection = .TopToBottom,
			childGap = 16,
			padding = {20, 20, 20, 20},
		},
	},
	) {
		// Top section: cURL input (1/4 height)
		// Calculate fixed width to prevent layout expansion from long text
		input_width := max(f32(windowWidth - SIDEBAR_WIDTH - 40), 100.0)

		if clay.UI()(
		{
			id = clay.ID("InputSection"),
			layout = {
				layoutDirection = .TopToBottom,
				sizing = {
					width = clay.SizingFixed(input_width),
					height = clay.SizingPercent(0.40),
				},
				childGap = 8,
			},
		},
		) {
			// Header with Save button
			if clay.UI()(
			{
				id = clay.ID("InputHeader"),
				layout = {sizing = {width = clay.SizingGrow({})}, childAlignment = {y = .Center}},
			},
			) {
				clay.Text(
					"cURL Command",
					clay.TextConfig(
						{textColor = COLOR_TEXT, fontSize = 20, fontId = FONT_ID_BODY_20},
					),
				)
			}

			// Input area with vertical scrolling
			input_bg := focused_input == .CurlInput ? COLOR_INPUT_FOCUS : COLOR_INPUT
			curl_scroll_id := clay.ID("CurlInputBox")
			curl_scroll := clay.GetScrollContainerData(curl_scroll_id)
			curl_scroll_offset: clay.Vector2 = {0, 0}
			if curl_scroll.found && curl_scroll.scrollPosition != nil {
				curl_scroll_offset = curl_scroll.scrollPosition^
			}

			if clay.UI()(
			{
				id = curl_scroll_id,
				layout = {
					layoutDirection = .TopToBottom,
					sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					padding = {12, 12, 12, 12},
				},
				backgroundColor = input_bg,
				cornerRadius = {6, 6, 6, 6},
				clip = {vertical = true, childOffset = curl_scroll_offset},
			},
			) {
				curl_text := editor_get_text(&app_state.curl_editor)
				if len(app_state.curl_editor.text) > 0 {
					// Tokenize the curl command (returns processed string with backslashes removed)
					tokens, processed_text := tokenize_curl(curl_text, context.temp_allocator)
					display_lines := format_display_lines(
						processed_text,
						tokens[:],
						input_width - 24,
						measure_text_for_wrap,
						context.temp_allocator,
					)

					// Render each display line
					for line_idx := 0; line_idx < len(display_lines); line_idx += 1 {
						line := display_lines[line_idx]

						// Create a horizontal layout for this line
						if clay.UI()(
						{
							id = clay.ID("CurlLine", u32(line_idx)),
							layout = {
								layoutDirection = .LeftToRight,
								sizing = {
									width = clay.SizingGrow({}),
									height = clay.SizingFit({}),
								},
							},
						},
						) {
							// Add indentation if needed
							if line.indent > 0 {
								clay.Text(
									"     ", // 5 spaces for continuation
									clay.TextConfig(
										{
											textColor = COLOR_TEXT,
											fontSize = 18,
											fontId = FONT_ID_BODY_18,
										},
									),
								)
							}

							// Render each token with its color
							for token_idx := 0; token_idx < len(line.tokens); token_idx += 1 {
								token := line.tokens[token_idx]
								text := processed_text[token.start:token.end]
								color := get_token_color(token.type, token.has_error)

								clay.TextDynamic(
									text,
									clay.TextConfig(
										{
											textColor = color,
											fontSize = 18,
											fontId = FONT_ID_BODY_18,
										},
									),
								)
							}

							// Ensure empty lines have height (for cursor position)
							if len(line.tokens) == 0 && line.indent == 0 {
								clay.Text(
									" ",
									clay.TextConfig({fontSize = 18, fontId = FONT_ID_BODY_18}),
								)
							}
						}
					}
				} else {
					clay.Text(
						"curl https://api.example.com/endpoint",
						clay.TextConfig(
							{
								textColor = COLOR_TEXT_DIM,
								fontSize = 18,
								fontId = FONT_ID_BODY_18,
								wrapMode = .Words,
							},
						),
					)
				}
			}

			// Buttons row
			if clay.UI()(
			{
				id = clay.ID("ButtonsRow"),
				layout = {
					sizing = {width = clay.SizingGrow({})},
					childGap = 8,
					padding = {0, 4, 0, 0},
					childAlignment = {x = .Right},
				},
			},
			) {
				// Run button
				if clay.UI()(
				{
					id = clay.ID("RunButton"),
					layout = {
						sizing = {width = clay.SizingFixed(90), height = clay.SizingFixed(32)},
						childAlignment = {x = .Center, y = .Center},
					},
					backgroundColor = app_state.request_state == .Loading ? COLOR_TEXT_DIM : COLOR_ACCENT,
					cornerRadius = {4, 4, 4, 4},
				},
				) {
					run_text := app_state.request_state == .Loading ? "..." : "Run"
					clay.TextDynamic(
						run_text,
						clay.TextConfig(
							{textColor = COLOR_TEXT, fontSize = 18, fontId = FONT_ID_BODY_18},
						),
					)
				}

				// Save button
				if clay.UI()(
				{
					id = clay.ID("SaveButton"),
					layout = {
						sizing = {width = clay.SizingFixed(90), height = clay.SizingFixed(32)},
						childAlignment = {x = .Center, y = .Center},
					},
					backgroundColor = COLOR_SUCCESS,
					cornerRadius = {4, 4, 4, 4},
				},
				) {
					clay.Text(
						"Save",
						clay.TextConfig(
							{textColor = COLOR_TEXT, fontSize = 18, fontId = FONT_ID_BODY_18},
						),
					)
				}
			}
		}

		// Response Section Title and Status
		if clay.UI()(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				layoutDirection = .LeftToRight,
				childAlignment = {y = .Center},
				childGap = 10,
			},
		},
		) {
			clay.Text(
				"Response",
				clay.TextConfig({textColor = COLOR_TEXT, fontSize = 24, fontId = FONT_ID_BODY_24}),
			)

			if app_state.request_state == .Success {
				status_color := COLOR_SUCCESS
				if app_state.status_code >= 400 {
					status_color = COLOR_ERROR
				} else if app_state.status_code >= 300 {
					status_color = COLOR_WARNING
				}

				status_text := fmt.tprintf("HTTP %d", app_state.status_code)
				clay.TextDynamic(
					status_text,
					clay.TextConfig(
						{textColor = status_color, fontSize = 18, fontId = FONT_ID_BODY_18},
					),
				)
			}
		}

		// Tabs and Copy Button Row
		if clay.UI()(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				layoutDirection = .LeftToRight,
				childAlignment = {y = .Center},
				childGap = 2, // Gap between tabs
			},
		},
		) {
			// Body Tab
			body_tab_color := app_state.active_tab == .Body ? COLOR_ACCENT : COLOR_PANEL
			if clay.UI()(
			{
				id = clay.ID("TabBody"),
				layout = {
					sizing = {width = clay.SizingFixed(100), height = clay.SizingFixed(32)},
					childAlignment = {x = .Center, y = .Center},
				},
				backgroundColor = body_tab_color,
				cornerRadius = {4, 4, 0, 0}, // Rounded top corners
			},
			) {
				clay.Text(
					"Body",
					clay.TextConfig(
						{textColor = COLOR_TEXT, fontSize = 16, fontId = FONT_ID_BODY_16},
					),
				)
			}

			// Headers Tab
			headers_tab_color := app_state.active_tab == .Headers ? COLOR_ACCENT : COLOR_PANEL
			if clay.UI()(
			{
				id = clay.ID("TabHeaders"),
				layout = {
					sizing = {width = clay.SizingFixed(100), height = clay.SizingFixed(32)},
					childAlignment = {x = .Center, y = .Center},
				},
				backgroundColor = headers_tab_color,
				cornerRadius = {4, 4, 0, 0}, // Rounded top corners
			},
			) {
				clay.Text(
					"Headers",
					clay.TextConfig(
						{textColor = COLOR_TEXT, fontSize = 16, fontId = FONT_ID_BODY_16},
					),
				)
			}

			// Spacer
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}

			// Copy Button (Context sensitive)
			if app_state.request_state == .Success {
				show_copy := false
				if app_state.active_tab == .Body && len(app_state.response_body) > 0 {
					show_copy = true
				} else if app_state.active_tab == .Headers && len(app_state.response_headers) > 0 {
					show_copy = true
				}

				if show_copy {
					if clay.UI()(
					{
						id = clay.ID("CopyButton"),
						layout = {
							sizing = {width = clay.SizingFixed(70), height = clay.SizingFixed(28)},
							childAlignment = {x = .Center, y = .Center},
						},
						backgroundColor = COLOR_ACCENT,
						cornerRadius = {4, 4, 4, 4},
					},
					) {
						clay.Text(
							"Copy",
							clay.TextConfig(
								{textColor = COLOR_TEXT, fontSize = 14, fontId = FONT_ID_BODY_14},
							),
						)
					}
				}
			}
		}

		// Content Area with Scrollbar
		// Get scroll data for this container
		scroll_id := clay.ID("ResponseContent")
		response_scroll := clay.GetScrollContainerData(scroll_id)
		scroll_offset: clay.Vector2 = {0, 0}
		if response_scroll.found && response_scroll.scrollPosition != nil {
			scroll_offset = response_scroll.scrollPosition^
		}

		// Horizontal wrapper for content + scrollbar
		if clay.UI()(
		{
			layout = {
				layoutDirection = .LeftToRight,
				sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			},
		},
		) {
			// Main scrollable content
			if clay.UI()(
			{
				id = scroll_id,
				layout = {
					layoutDirection = .TopToBottom,
					sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					padding = {12, 12, 12, 12},
				},
				backgroundColor = COLOR_PANEL,
				cornerRadius = {0, 0, 6, 6}, // Square top to merge with tab
				clip = {vertical = true, horizontal = true, childOffset = scroll_offset},
			},
			) {
				switch app_state.request_state {
				case .Idle:
					clay.Text(
						"Run a cURL command to see the response.",
						clay.TextConfig(
							{textColor = COLOR_TEXT_DIM, fontSize = 18, fontId = FONT_ID_BODY_18},
						),
					)
				case .Loading:
					clay.Text(
						"Executing request...",
						clay.TextConfig(
							{textColor = COLOR_TEXT_DIM, fontSize = 18, fontId = FONT_ID_BODY_18},
						),
					)
				case .Success:
					if app_state.active_tab == .Body {
						if len(app_state.response_body) > 0 {
							render_highlighted_json(app_state.response_body)
						} else {
							clay.Text(
								"No body returned.",
								clay.TextConfig(
									{
										textColor = COLOR_TEXT_DIM,
										fontSize = 16,
										fontId = FONT_ID_BODY_16,
									},
								),
							)
						}
					} else {
						if len(app_state.response_headers) > 0 {
							clay.TextDynamic(
								app_state.response_headers,
								clay.TextConfig(
									{
										textColor = COLOR_TEXT_DIM,
										fontSize = 14,
										fontId = FONT_ID_BODY_14,
									},
								),
							)
						} else {
							clay.Text(
								"No headers returned.",
								clay.TextConfig(
									{
										textColor = COLOR_TEXT_DIM,
										fontSize = 16,
										fontId = FONT_ID_BODY_16,
									},
								),
							)
						}
					}
				case .Error:
					clay.TextDynamic(
						app_state.error_message,
						clay.TextConfig(
							{textColor = COLOR_ERROR, fontSize = 18, fontId = FONT_ID_BODY_18},
						),
					)
				}
			}

			// Scrollbar track (only show if content overflows)
			if response_scroll.found &&
			   response_scroll.contentDimensions.height >
				   response_scroll.scrollContainerDimensions.height {
				// Calculate scrollbar metrics
				container_height := response_scroll.scrollContainerDimensions.height
				content_height := response_scroll.contentDimensions.height
				scroll_y := -scroll_offset.y // Scroll offset is negative

				// Thumb height proportional to visible area
				thumb_height := max(30, container_height * (container_height / content_height))
				// Thumb position proportional to scroll
				scrollable_range := content_height - container_height
				thumb_offset := (scroll_y / scrollable_range) * (container_height - thumb_height)
				thumb_offset = clamp(thumb_offset, 0, container_height - thumb_height)

				// Scrollbar track
				if clay.UI()(
				{
					id = clay.ID("ScrollbarTrack"),
					layout = {
						sizing = {width = clay.SizingFixed(8), height = clay.SizingGrow({})},
						padding = {0, 0, u16(thumb_offset), 0}, // Top padding for thumb position
					},
					backgroundColor = {50, 50, 55, 255},
					cornerRadius = {4, 4, 4, 4},
				},
				) {
					// Scrollbar thumb
					if clay.UI()(
					{
						id = clay.ID("ScrollbarThumb"),
						layout = {
							sizing = {
								width = clay.SizingFixed(8),
								height = clay.SizingFixed(thumb_height),
							},
						},
						backgroundColor = {100, 110, 130, 255},
						cornerRadius = {4, 4, 4, 4},
					},
					) {}
				}
			}
		}
	}
}

// Main layout
create_layout :: proc() -> clay.ClayArray(clay.RenderCommand) {
	clay.BeginLayout()

	if clay.UI()(
	{
		id = clay.ID("OuterContainer"),
		layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
		backgroundColor = COLOR_BG,
	},
	) {
		sidebar_component()
		main_content_component()
	}

	return clay.EndLayout()
}

// Calculate text width for cursor positioning
// Calculate text width for cursor positioning
calculate_text_width :: proc(text: []u8, length: int, font_size: u16) -> f32 {
	if length <= 0 {return 0}

	font := g_font
	scale_factor := f32(font_size) / f32(font.baseSize)
	width: f32 = 0

	for i in 0 ..< length {
		char := text[i]
		if char < 32 {continue}
		glyph_index := char - 32
		glyph := font.glyphs[glyph_index]

		if glyph.advanceX != 0 {
			width += f32(glyph.advanceX) * scale_factor
		} else {
			width += (font.recs[glyph_index].width + f32(glyph.offsetX)) * scale_factor
		}
	}

	return width // No extra scaling, assuming 1:1 if we scaled correctly
}

// Helper for wrapping measurement
measure_text_for_wrap :: proc(text: string) -> f32 {
	return calculate_text_width(transmute([]u8)text, len(text), 18)
}


// Helper to get glyph width
// Helper to get glyph width
get_glyph_width :: proc(font: raylib.Font, char: u8, scale_factor: f32) -> f32 {
	if char < 32 {return 0}
	glyph_index := char - 32
	glyph := font.glyphs[glyph_index]

	if glyph.advanceX != 0 {
		return f32(glyph.advanceX) * scale_factor
	} else {
		return (font.recs[glyph_index].width + f32(glyph.offsetX)) * scale_factor
	}
}


// Calculate cursor position from click X,Y coordinates
calculate_cursor_from_click :: proc(
	text: []u8,
	length: int,
	click_x: f32,
	click_y: f32,
	container_width: f32, // Unused for wrapping now
	font_id: u16,
	font_size: u16,
) -> int {
	if length <= 0 {return 0}

	font := g_font
	scale_factor := f32(font_size) / f32(font.baseSize)
	line_height := f32(font_size)


	// We strictly use the display lines for hit testing
	text_str := string(text[:length])
	tokens, processed_text := tokenize_curl(text_str, context.temp_allocator)
	display_lines := format_display_lines(
		processed_text,
		tokens[:],
		container_width,
		measure_text_for_wrap,
		context.temp_allocator,
	)

	current_y: f32 = 0

	// 1. Find the Line
	target_line_idx := -1
	for i := 0; i < len(display_lines); i += 1 {
		if click_y >= current_y && click_y < current_y + line_height {
			target_line_idx = i
			break
		}
		current_y += line_height
	}

	if target_line_idx == -1 {
		// Clicked below all lines, go to end
		return length
	}

	// 2. Find the Char in Line
	line := display_lines[target_line_idx]
	current_x: f32 = f32(line.indent) * get_glyph_width(font, ' ', scale_factor) // Start with indentation


	// If clicked before indentation
	if click_x < current_x {
		// Return start of first token in line
		if len(line.tokens) > 0 {
			// Map back to raw index... tricky.
			// Let's assume for now 1:1 if no backslashes.
			// We need a robust way to map.
			return line.tokens[0].start
		}
		return 0 // Should not happen if lines exist
	}

	for token in line.tokens {
		token_text := processed_text[token.start:token.end]

		for i := 0; i < len(token_text); i += 1 {
			char := token_text[i]
			char_width := get_glyph_width(font, u8(char), scale_factor)


			// Center hit test
			if click_x < current_x + char_width { 	// Hit this char.
				// Return index.
				// Index is into PROCESSED text which is now SAME as raw text
				return token.start + i
			}

			current_x += char_width
		}
	}

	// Clicked past end of line content
	if len(line.tokens) > 0 {
		last_token := line.tokens[len(line.tokens) - 1]
		return last_token.end
	}

	return length
}

// Helper to map index removed - raw and process are now 1:1

// Helper to map raw index to processed index removed

// Calculate position (x, y) for a given index in wrapped text
calculate_wrapped_position :: proc(
	text: []u8,
	target_index: int,
	container_width: f32, // Unused
	font_id: u16,
	font_size: u16,
) -> (
	f32,
	f32,
) {
	if target_index < 0 {return 0, 0}

	// Use tokenizer layout
	text_str := string(text)
	tokens, processed_text := tokenize_curl(text_str, context.temp_allocator)
	display_lines := format_display_lines(
		processed_text,
		tokens[:],
		container_width,
		measure_text_for_wrap,
		context.temp_allocator,
	)

	// Map raw target index to processed index -> 1:1 mapping now
	target_processed := target_index

	font := g_font
	scale_factor := f32(font_size) / f32(font.baseSize)
	line_height := f32(font_size)


	current_y: f32 = 0

	// Find where this index falls
	for line in display_lines {
		current_x := f32(line.indent) * get_glyph_width(font, ' ', scale_factor)


		for token in line.tokens {
			token_len := token.end - token.start

			// If target is within this token
			if target_processed >= token.start && target_processed <= token.end {
				// Calculate offset within token
				offset := target_processed - token.start
				token_text := processed_text[token.start:token.end]

				for i := 0; i < offset; i += 1 {
					current_x += get_glyph_width(font, u8(token_text[i]), scale_factor)
				}

				return current_x, current_y
			}

			// Advance X by full token width
			token_text := processed_text[token.start:token.end]
			for char in token_text {
				current_x += get_glyph_width(font, u8(char), scale_factor)
			}

		}

		// If target is exactly at the end of this line's content (and not found in tokens above)
		// Check if map points to end of last token?
		if len(line.tokens) > 0 {
			last_token := line.tokens[len(line.tokens) - 1]
			if target_processed == last_token.end {
				return current_x, current_y
			}
		}

		// If empty line (just indentation?)
		if len(line.tokens) == 0 && target_processed == 0 {
			// Should verify if this ever happens for implicit empty lines?
		}

		current_y += line_height
	}

	// If not found (e.g. at very end), return end of last line
	if len(display_lines) > 0 {
		// Actually current_x/y would be at start of next line loop if we exited.
		last_line := display_lines[len(display_lines) - 1]
		end_x: f32 = f32(last_line.indent) * get_glyph_width(font, ' ', scale_factor)
		// Add width of all tokens
		for token in last_line.tokens {
			token_text := processed_text[token.start:token.end]
			for char in token_text {
				end_x += get_glyph_width(font, u8(char), scale_factor)
			}
		}

		return end_x, f32(len(display_lines) - 1) * line_height
	}

	return 0, 0
}

// Calculate linear position (x) for a given index in single-line text
calculate_linear_position :: proc(
	text: []u8,
	target_index: int,
	font_id: u16,
	font_size: u16,
) -> f32 {
	if target_index <= 0 {return 0}

	font := g_font
	scale_factor := f32(font_size) / f32(font.baseSize)


	// Convert bytes to string for iteration (assuming UTF-8 safe or similar)
	text_str := string(text)

	// If target index is beyond length, clamp it
	actual_target := min(target_index, len(text))

	current_x: f32 = 0

	// Need to iterate glyphs up to target index
	// We iterate bytes but advanced by glyph width
	// This simple loop assumes 1 byte chars for width lookup or similar,
	// typically we iterate over the string safely.

	// Using a specific iteration:
	if actual_target > 0 {
		str_slice := text_str[:actual_target]
		for char in str_slice {
			current_x += get_glyph_width(font, u8(char), scale_factor)
		}

	}

	return current_x
}

// Calculate cursor index from click X coordinate for single-line text
calculate_linear_cursor_from_click :: proc(
	text: []u8,
	length: int,
	click_x: f32,
	font_id: u16,
	font_size: u16,
) -> int {
	if length <= 0 {return 0}

	font := g_font
	scale_factor := f32(font_size) / f32(font.baseSize)

	text_str := string(text[:length])


	current_x: f32 = 0

	for i := 0; i < len(text_str); i += 1 {
		char := text_str[i]
		char_width := get_glyph_width(font, u8(char), scale_factor)


		// If click is within the left half of this char, return this index (cursor before char)
		// If click is within right half, continue (effectively checking next boundary)
		// Actually standard behavior: if x < center of char, return start.

		center_x := current_x + (char_width / 2)

		if click_x < center_x {
			return i
		}

		current_x += char_width
	}

	// If we are here, we clicked past the center of the last char
	return length
}

// Draw blinking cursor for focused input
draw_text_cursor :: proc() {
	// Only draw if we have focus
	if focused_input == .None {return}

	// Get the appropriate element bounding box, cursor position, and selection anchor
	element_id: clay.ElementId
	cursor_pos: int
	text_buffer: []u8
	text_len: int
	font_id: u16
	padding_left: f32 = 0
	padding_top: f32 = 0
	scroll_offset_x: f32 = 0
	sel_anchor: Maybe(int)

	switch focused_input {
	case .Search:
		element_id = clay.ID("SearchBox")
		cursor_pos = app_state.search_cursor
		text_buffer = app_state.search_text[:]
		text_len = app_state.search_len
		font_id = FONT_ID_BODY_18
		padding_left = 10
		padding_top = 8
		sel_anchor = app_state.search_sel_anchor
	case .CurlInput:
		element_id = clay.ID("CurlInputBox")
		cursor_pos = app_state.curl_editor.cursor
		text_buffer = app_state.curl_editor.text[:]
		text_len = len(app_state.curl_editor.text)
		font_id = FONT_ID_BODY_18
		padding_left = 12
		padding_top = 12
		sel_anchor = app_state.curl_editor.selection_anchor
	case .NameInput:
		// For editing saved command names
		if editing_id, ok := app_state.editing_id.?; ok {
			element_id = clay.ID("CmdName", editing_id)
		} else {
			return
		}
		cursor_pos = app_state.name_cursor
		text_buffer = app_state.name_input[:]
		text_len = app_state.name_input_len
		font_id = FONT_ID_BODY_18
		padding_left = 0

		// improved vertical centering logic
		// We'll calculate it later based on bounds
		padding_top = 0

		scroll_offset_x = app_state.name_input_scroll_x
		sel_anchor = app_state.name_sel_anchor
	case .None:
		return
	}

	// Get element bounds
	bounds_data := clay.GetElementData(element_id)
	if !bounds_data.found {return}

	bounds := bounds_data.boundingBox
	cursor_height: f32 = 18 // Match font size

	// For NameInput, center vertically
	if focused_input == .NameInput {
		padding_top = (bounds.height - cursor_height) / 2
	}


	// Determine available width for text
	container_width := bounds.width - (padding_left * 2)

	// Draw selection highlight if there is a selection
	if anchor_pos, ok := sel_anchor.?; ok && anchor_pos != cursor_pos {
		sel_start := min(anchor_pos, cursor_pos)
		sel_end := max(anchor_pos, cursor_pos)

		// Naive single-rectangle approach for short/single-line selections,
		// or smarter multi-rect for wrapped selections.

		start_x, start_y := calculate_wrapped_position(
			text_buffer[:text_len],
			sel_start,
			container_width,
			font_id,
			18,
		)
		end_x, end_y := calculate_wrapped_position(
			text_buffer[:text_len],
			sel_end,
			container_width,
			font_id,
			18,
		)

		abs_start_x := bounds.x + padding_left + start_x
		abs_start_y := bounds.y + padding_top + start_y

		// If selection spans multiple lines
		if start_y != end_y {
			// Draw first line segment (cursor to end of line)
			raylib.DrawRectangleRec(
				{
					abs_start_x,
					abs_start_y,
					(bounds.x + padding_left + container_width) - abs_start_x,
					cursor_height,
				},
				{80, 120, 200, 150},
			)

			// Draw full middle lines
			curr_y := start_y + cursor_height
			for curr_y < end_y {
				raylib.DrawRectangleRec(
					{
						bounds.x + padding_left,
						bounds.y + padding_top + curr_y,
						container_width,
						cursor_height,
					},
					{80, 120, 200, 150},
				)
				curr_y += cursor_height
			}

			// Draw last line segment (start of line to cursor)
			raylib.DrawRectangleRec(
				{bounds.x + padding_left, bounds.y + padding_top + end_y, end_x, cursor_height},
				{80, 120, 200, 150},
			)
		} else {
			// Single line selection
			raylib.DrawRectangleRec(
				{abs_start_x, abs_start_y, end_x - start_x, cursor_height},
				{80, 120, 200, 150},
			)
		}
	}

	// Only draw cursor if in "on" phase of blink
	if app_state.cursor_blink_timer > 0.5 {return}

	// Calculate cursor X position based on text before cursor
	rel_x: f32 = 0
	rel_y: f32 = 0

	if focused_input == .NameInput {
		rel_x = calculate_linear_position(text_buffer[:text_len], cursor_pos, font_id, 18)
		// rel_y remains 0 for linear single line (centered via padding_top)
	} else {
		rx, ry := calculate_wrapped_position(
			text_buffer[:text_len],
			cursor_pos,
			container_width,
			font_id,
			18,
		)
		rel_x = rx
		rel_y = ry
	}

	// Apply scroll offset
	rel_x -= scroll_offset_x

	cursor_x := bounds.x + padding_left + rel_x
	cursor_y := bounds.y + padding_top + rel_y

	// Draw the cursor line
	raylib.DrawLineEx(
		{cursor_x, cursor_y},
		{cursor_x, cursor_y + cursor_height},
		2,
		clay_color_to_rl_color(COLOR_TEXT),
	)
}

// Handle click interactions
deprecated_handle_interactions :: proc() {
	// Check search box click and drag for selection
	if clay.PointerOver(clay.ID("SearchBox")) {
		bounds_data := clay.GetElementData(clay.ID("SearchBox"))
		if bounds_data.found {
			mouse_x := raylib.GetMousePosition().x
			mouse_y := raylib.GetMousePosition().y
			click_x := mouse_x - bounds_data.boundingBox.x - 10 // padding
			click_y := mouse_y - bounds_data.boundingBox.y - 10 // padding

			new_cursor := calculate_cursor_from_click(
				app_state.search_text[:],
				app_state.search_len,
				click_x,
				click_y,
				bounds_data.boundingBox.width - 20,
				FONT_ID_BODY_18,
				18,
			)

			if raylib.IsMouseButtonPressed(.LEFT) {
				focused_input = .Search
				// Start selection - set anchor and cursor to same position
				app_state.search_sel_anchor = new_cursor
				app_state.search_cursor = new_cursor
			} else if raylib.IsMouseButtonDown(.LEFT) && focused_input == .Search {
				// Dragging - update cursor position (anchor stays at start)
				app_state.search_cursor = new_cursor
			}
		}
	}

	// Check curl input click and drag for selection
	if clay.PointerOver(clay.ID("CurlInputBox")) {
		bounds_data := clay.GetElementData(clay.ID("CurlInputBox"))
		if bounds_data.found {
			mouse_x := raylib.GetMousePosition().x
			mouse_y := raylib.GetMousePosition().y
			click_x := mouse_x - bounds_data.boundingBox.x - 12 // padding_x
			click_y := mouse_y - bounds_data.boundingBox.y - 12 // padding_y

			new_cursor := calculate_cursor_from_click(
				app_state.curl_editor.text[:],
				len(app_state.curl_editor.text),
				click_x,
				click_y,
				bounds_data.boundingBox.width - 24, // width minus padding
				FONT_ID_BODY_18,
				18,
			)

			if raylib.IsMouseButtonPressed(.LEFT) {
				focused_input = .CurlInput
				// Start selection - set anchor and cursor to same position
				app_state.curl_editor.selection_anchor = new_cursor
				app_state.curl_editor.cursor = new_cursor
			} else if raylib.IsMouseButtonDown(.LEFT) && focused_input == .CurlInput {
				// Dragging - update cursor position (anchor stays at start)
				app_state.curl_editor.cursor = new_cursor
			}
		}
	}

	// Check Run button click
	if clay.PointerOver(clay.ID("RunButton")) {
		if raylib.IsMouseButtonPressed(.LEFT) {
			if app_state.request_state != .Loading {
				execute_curl_command()
			}
		}
	}

	// Check Save button click
	if clay.PointerOver(clay.ID("SaveButton")) {
		if raylib.IsMouseButtonPressed(.LEFT) {
			save_current_command()
		}
	}

	// Check Tab clicks
	if clay.PointerOver(clay.ID("TabBody")) {
		if raylib.IsMouseButtonPressed(.LEFT) {
			app_state.active_tab = .Body
		}
	}
	if clay.PointerOver(clay.ID("TabHeaders")) {
		if raylib.IsMouseButtonPressed(.LEFT) {
			app_state.active_tab = .Headers
		}
	}

	// Check Copy button click (context sensitive)
	if clay.PointerOver(clay.ID("CopyButton")) {
		if raylib.IsMouseButtonPressed(.LEFT) {
			text_to_copy := ""
			if app_state.active_tab == .Body {
				text_to_copy = app_state.response_body
			} else {
				text_to_copy = app_state.response_headers
			}

			if len(text_to_copy) > 0 {
				cstr := strings.clone_to_cstring(text_to_copy)
				defer delete(cstr)
				raylib.SetClipboardText(cstr)
			}
		}
	}

	// Check command item clicks (Edit, Delete, Save, Select)
	for &cmd in app_state.commands {
		// Edit button click
		if clay.PointerOver(clay.ID("EditBtn", cmd.id)) {
			if raylib.IsMouseButtonPressed(.LEFT) {
				start_editing_command(&cmd)
				return // Stop processing other clicks
			}
		}

		// Delete button click
		if clay.PointerOver(clay.ID("DelBtn", cmd.id)) {
			if raylib.IsMouseButtonPressed(.LEFT) {
				delete_command(&app_state, cmd.id)
				app_state.selected_id = nil
				return // Stop processing other clicks
			}
		}

		// Save name button click (when editing)
		if clay.PointerOver(clay.ID("SaveNameBtn", cmd.id)) {
			if raylib.IsMouseButtonPressed(.LEFT) {
				save_editing_command()
				return // Stop processing other clicks
			}
		}

		// Check for clicks on the command name (when editing)
		if editing_id, ok := app_state.editing_id.?; ok && editing_id == cmd.id {
			if clay.PointerOver(clay.ID("CmdName", cmd.id)) {
				bounds_data := clay.GetElementData(clay.ID("CmdName", cmd.id))
				if bounds_data.found {
					mouse_x := raylib.GetMousePosition().x
					mouse_y := raylib.GetMousePosition().y

					// Adjust click by scroll offset
					click_x := mouse_x - bounds_data.boundingBox.x + app_state.name_input_scroll_x

					// Use linear calculation
					new_cursor := calculate_linear_cursor_from_click(
						app_state.name_input[:],
						app_state.name_input_len,
						click_x,
						FONT_ID_BODY_18,
						18,
					)

					if raylib.IsMouseButtonPressed(.LEFT) {
						app_state.name_cursor = new_cursor
						app_state.name_sel_anchor = new_cursor
						focused_input = .NameInput // Ensure focus
						app_state.cursor_blink_timer = 0 // Reset blink timer
					} else if raylib.IsMouseButtonDown(.LEFT) {
						// Drag selection
						app_state.name_cursor = new_cursor
					}
				}
			}
		}

		// Command item click (select)
		if clay.PointerOver(clay.ID("CmdItem", cmd.id)) {
			if raylib.IsMouseButtonPressed(.LEFT) {
				// Only select if not clicking buttons or editing name
				is_editing := false
				if eid, ok := app_state.editing_id.?; ok && eid == cmd.id {
					is_editing = true
				}

				clicked_name_while_editing :=
					is_editing && clay.PointerOver(clay.ID("CmdName", cmd.id))

				if !clay.PointerOver(clay.ID("EditBtn", cmd.id)) &&
				   !clay.PointerOver(clay.ID("DelBtn", cmd.id)) &&
				   !clay.PointerOver(clay.ID("SaveNameBtn", cmd.id)) &&
				   !clicked_name_while_editing {
					load_command(&cmd)
				}
			}
		}
	}

	// Track keyboard input for focused field
	#partial switch focused_input {
	case .Search:
		handle_text_input(
			app_state.search_text[:],
			&app_state.search_len,
			256,
			&app_state.search_cursor,
			&app_state.search_sel_anchor,
		)
	case .CurlInput:
		// Get element data for width
		bounds_data := clay.GetElementData(clay.ID("CurlInputBox"))
		width: f32 = 0
		if bounds_data.found {
			width = bounds_data.boundingBox.width - 24
		}

		editor_handle_input(&app_state.curl_editor, width, FONT_ID_BODY_18, 18)

		// Check for run command (Ctrl+Enter is handled in editor_handle_input for newlines, but we want it to run?)
		// editor_handle_input handles basic typing.
		// If we want Ctrl+Enter to RUN, we should check it here OR inside editor (and return a flag/callback).
		// Current editor implementation does NOT consume Ctrl+Enter for newlines, it lets it pass if !ctrl.
		// Implementation in editor.odin:
		// if raylib.IsKeyPressed(.ENTER) ... { if !ctrl { insert("\n") } }
		// So Ctrl+Enter does nothing in editor. We can catch it here.

		if raylib.IsKeyPressed(.ENTER) && raylib.IsKeyDown(.LEFT_CONTROL) {
			execute_curl_command()
		}
	case .NameInput:
		handle_text_input(
			app_state.name_input[:],
			&app_state.name_input_len,
			256,
			&app_state.name_cursor,
			&app_state.name_sel_anchor,
		)

		// Calculate scroll offset to keep cursor in view
		// Get element width (approximate or look up)
		// We'll assume the input width is constrained by the sidebar minus buttons
		// Sidebar is 280, padding 12*2, item padding 10*2 = 236 available
		// Edit button is 50, Save button is 50.
		// If editing, we have Save button (50) + gap.
		// Let's rely on Clay getting the element data if possible, or estimate.

		input_width: f32 = 0
		if editing_id, ok := app_state.editing_id.?; ok {
			bounds_data := clay.GetElementData(clay.ID("CmdName", editing_id))
			if bounds_data.found {
				input_width = bounds_data.boundingBox.width
			}
		}

		if input_width > 0 {
			// Calculate text width before cursor
			cursor_x := calculate_text_width(app_state.name_input[:], app_state.name_cursor, 18)


			// Add some padding/margin for cursor visibility
			margin: f32 = 10

			// If cursor is to the right of the visible area
			if cursor_x > app_state.name_input_scroll_x + input_width - margin {
				app_state.name_input_scroll_x = cursor_x - input_width + margin
			}

			// If cursor is to the left of the visible area
			if cursor_x < app_state.name_input_scroll_x + margin {
				app_state.name_input_scroll_x = max(0, cursor_x - margin)
			}
		}

		// Enter to save
		if raylib.IsKeyPressed(.ENTER) {
			save_editing_command()
		}
	}

	// Click outside to unfocus
	if raylib.IsMouseButtonPressed(.LEFT) {
		if !clay.PointerOver(clay.ID("SearchBox")) && !clay.PointerOver(clay.ID("CurlInputBox")) {
			focused_input = .None
		}
	}

	// Escape to unfocus or cancel edit
	if raylib.IsKeyPressed(.ESCAPE) {
		if app_state.editing_id != nil {
			app_state.editing_id = nil
		}
		focused_input = .None
	}

	// Scrollbar drag handling
	scroll_id := clay.ID("ResponseContent")
	response_scroll := clay.GetScrollContainerData(scroll_id)

	if response_scroll.found && response_scroll.scrollPosition != nil {
		container_height := response_scroll.scrollContainerDimensions.height
		content_height := response_scroll.contentDimensions.height

		if content_height > container_height {
			// Handle scrollbar thumb drag start
			if clay.PointerOver(clay.ID("ScrollbarThumb")) ||
			   clay.PointerOver(clay.ID("ScrollbarTrack")) {
				if raylib.IsMouseButtonPressed(.LEFT) {
					app_state.scrollbar_dragging = true
					app_state.scrollbar_drag_start_y = raylib.GetMousePosition().y
					app_state.scrollbar_scroll_start_y = response_scroll.scrollPosition^.y
				}
			}

			// Handle drag motion
			if app_state.scrollbar_dragging {
				if raylib.IsMouseButtonDown(.LEFT) {
					mouse_y := raylib.GetMousePosition().y
					delta_y := mouse_y - app_state.scrollbar_drag_start_y

					// Calculate the ratio of mouse movement to content scroll
					// Thumb height proportional to visible area
					thumb_height := max(30, container_height * (container_height / content_height))
					track_usable_height := container_height - thumb_height
					scrollable_range := content_height - container_height

					// Convert mouse delta to scroll delta
					scroll_ratio := scrollable_range / track_usable_height
					scroll_delta := delta_y * scroll_ratio

					// Update scroll position
					new_scroll_y := app_state.scrollbar_scroll_start_y - scroll_delta
					new_scroll_y = clamp(new_scroll_y, -(content_height - container_height), 0)
					response_scroll.scrollPosition^.y = new_scroll_y
				} else {
					// Mouse released, stop dragging
					app_state.scrollbar_dragging = false
				}
			}
		}
	}

	// Stop dragging if mouse released anywhere
	if raylib.IsMouseButtonReleased(.LEFT) {
		app_state.scrollbar_dragging = false
		app_state.sidebar_scrollbar_dragging = false
	}

	// Sidebar scrollbar drag handling
	sidebar_scroll_id := clay.ID("CommandsList")
	sidebar_scroll := clay.GetScrollContainerData(sidebar_scroll_id)

	if sidebar_scroll.found && sidebar_scroll.scrollPosition != nil {
		container_height := sidebar_scroll.scrollContainerDimensions.height
		content_height := sidebar_scroll.contentDimensions.height

		if content_height > container_height {
			// Handle sidebar scrollbar thumb drag start
			if clay.PointerOver(clay.ID("SidebarScrollbarThumb")) ||
			   clay.PointerOver(clay.ID("SidebarScrollbarTrack")) {
				if raylib.IsMouseButtonPressed(.LEFT) {
					app_state.sidebar_scrollbar_dragging = true
					app_state.sidebar_scrollbar_drag_start_y = raylib.GetMousePosition().y
					app_state.sidebar_scrollbar_scroll_start_y = sidebar_scroll.scrollPosition^.y
				}
			}

			// Handle drag motion
			if app_state.sidebar_scrollbar_dragging {
				if raylib.IsMouseButtonDown(.LEFT) {
					mouse_y := raylib.GetMousePosition().y
					delta_y := mouse_y - app_state.sidebar_scrollbar_drag_start_y

					// Calculate the ratio of mouse movement to content scroll
					thumb_height := max(30, container_height * (container_height / content_height))
					track_usable_height := container_height - thumb_height
					scrollable_range := content_height - container_height

					// Convert mouse delta to scroll delta
					scroll_ratio := scrollable_range / track_usable_height
					scroll_delta := delta_y * scroll_ratio

					// Update scroll position
					new_scroll_y := app_state.sidebar_scrollbar_scroll_start_y - scroll_delta
					new_scroll_y = clamp(new_scroll_y, -(content_height - container_height), 0)
					sidebar_scroll.scrollPosition^.y = new_scroll_y
				} else {
					app_state.sidebar_scrollbar_dragging = false
				}
			}
		}
	}
}

// Start editing a command name
start_editing_command :: proc(cmd: ^SavedCommand) {
	app_state.editing_id = cmd.id
	focused_input = .NameInput

	// Copy current name to input buffer
	cmd_bytes := transmute([]u8)cmd.name
	copy(app_state.name_input[:], cmd_bytes)
	app_state.name_input_len = len(cmd.name)

	app_state.name_cursor = app_state.name_input_len
	app_state.name_sel_anchor = nil
	app_state.name_input_scroll_x = 0
}

// Save the currently editing command
save_editing_command :: proc() {
	if editing_id, ok := app_state.editing_id.?; ok {
		new_name := buffer_to_string(app_state.name_input[:], app_state.name_input_len)
		if app_state.name_input_len > 0 {
			// Find the command (recursive)
			if cmd_ptr := find_command(&app_state, editing_id); cmd_ptr != nil {
				// Determine command content
				new_command := ""
				must_free := false

				if selected_id, sel_ok := app_state.selected_id.?;
				   sel_ok && selected_id == editing_id {
					// From editor - safe to pass directly as it's separate memory
					new_command = editor_get_text(&app_state.curl_editor)
				} else {
					// From existing command - MUST clone to avoid Use-After-Free
					// because update_command frees the old cmd_ptr.command
					new_command = strings.clone(cmd_ptr.command)
					must_free = true
				}

				update_command(&app_state, editing_id, new_name, new_command)

				if must_free {
					delete(new_command)
				}
			}
		}
		app_state.editing_id = nil
		focused_input = .None
	}
}

// Execute the current cURL command
execute_curl_command :: proc() {
	if len(app_state.curl_editor.text) == 0 {return}

	// Clear previous response
	// Clear previous response
	if len(app_state.response_headers) > 0 {
		delete(app_state.response_headers)
		app_state.response_headers = ""
	}
	if len(app_state.response_body) > 0 {
		delete(app_state.response_body)
		app_state.response_body = ""
	}
	if len(app_state.error_message) > 0 {
		delete(app_state.error_message)
		app_state.error_message = ""
	}

	app_state.request_state = .Loading

	command := editor_get_text(&app_state.curl_editor)

	// Clone command to heap to pass to thread
	cmd_ptr := new(string)
	cmd_ptr^ = strings.clone(command)

	app_state.worker_thread = thread.create(run_curl_task)
	if app_state.worker_thread != nil {
		app_state.worker_thread.data = cast(rawptr)cmd_ptr
		thread.start(app_state.worker_thread)
	} else {
		app_state.request_state = .Error
		app_state.error_message = strings.clone("Failed to create worker thread")
		free(cmd_ptr)
	}
}

// Thread procedure
run_curl_task :: proc(t: ^thread.Thread) {
	cmd_ptr := cast(^string)t.data
	command := cmd_ptr^

	result := run_curl(command)

	sync.mutex_lock(&app_state.worker_mutex)
	app_state.worker_result = result
	sync.mutex_unlock(&app_state.worker_mutex)

	delete(command)
	free(cmd_ptr)
}

// Save current command
save_current_command :: proc() {
	if len(app_state.curl_editor.text) == 0 {return}

	command := editor_get_text(&app_state.curl_editor)

	// If a command is selected, update it instead of creating a new one
	if selected_id, ok := app_state.selected_id.?; ok {
		// Find the command to get its current name (recursive)
		if cmd_ptr := find_command(&app_state, selected_id); cmd_ptr != nil {
			// Clone name to avoid Use-After-Free in update_command
			// (update_command frees cmd.name, so we can't pass cmd.name directly if it points to the same memory)
			current_name := strings.clone(cmd_ptr.name)
			defer delete(current_name)

			update_command(&app_state, selected_id, current_name, command)
			return
		}
	}

	// Use first 10 characters of command as default name (or less if command is shorter)
	name_len := min(len(command), 10)
	name := strings.clone(command[:name_len])
	add_command_root(&app_state, name, command)
}

// Load a saved command into the input
load_command :: proc(cmd: ^SavedCommand) {
	app_state.selected_id = cmd.id

	// Copy command to editor
	editor_set_text(&app_state.curl_editor, cmd.command)
}

clay_raylib_render :: proc(
	render_commands: ^clay.ClayArray(clay.RenderCommand),
	allocator := context.temp_allocator,
) {
	for i in 0 ..< render_commands.length {
		render_command := clay.RenderCommandArray_Get(render_commands, i)
		bounds := render_command.boundingBox

		switch render_command.commandType {
		case .None:
		case .Text:
			config := render_command.renderData.text

			text := string(config.stringContents.chars[:config.stringContents.length])

			cstr_text := strings.clone_to_cstring(text, allocator)

			raylib.DrawTextEx(
				g_font,
				cstr_text,
				{bounds.x, bounds.y},
				f32(config.fontSize),
				f32(config.letterSpacing), // Consider if letterSpacing needs scaling too? Usually pixels.
				clay_color_to_rl_color(config.textColor),
			)
		case .Image:
			config := render_command.renderData.image
			tint := config.backgroundColor
			if tint == 0 {
				tint = {255, 255, 255, 255}
			}

			imageTexture := (^raylib.Texture2D)(config.imageData)
			raylib.DrawTextureEx(
				imageTexture^,
				{bounds.x, bounds.y},
				0,
				bounds.width / f32(imageTexture.width),
				clay_color_to_rl_color(tint),
			)
		case .ScissorStart:
			raylib.BeginScissorMode(
				i32(math.round(bounds.x)),
				i32(math.round(bounds.y)),
				i32(math.round(bounds.width)),
				i32(math.round(bounds.height)),
			)
		case .ScissorEnd:
			raylib.EndScissorMode()
		case .Rectangle:
			config := render_command.renderData.rectangle
			if config.cornerRadius.topLeft > 0 {
				radius: f32 = (config.cornerRadius.topLeft * 2) / min(bounds.width, bounds.height)
				draw_rect_rounded(
					bounds.x,
					bounds.y,
					bounds.width,
					bounds.height,
					radius,
					config.backgroundColor,
				)
			} else {
				draw_rect(bounds.x, bounds.y, bounds.width, bounds.height, config.backgroundColor)
			}
		case .Border:
			config := render_command.renderData.border
			if config.width.left > 0 {
				draw_rect(
					bounds.x,
					bounds.y + config.cornerRadius.topLeft,
					f32(config.width.left),
					bounds.height - config.cornerRadius.topLeft - config.cornerRadius.bottomLeft,
					config.color,
				)
			}
			if config.width.right > 0 {
				draw_rect(
					bounds.x + bounds.width - f32(config.width.right),
					bounds.y + config.cornerRadius.topRight,
					f32(config.width.right),
					bounds.height - config.cornerRadius.topRight - config.cornerRadius.bottomRight,
					config.color,
				)
			}
			if config.width.top > 0 {
				draw_rect(
					bounds.x + config.cornerRadius.topLeft,
					bounds.y,
					bounds.width - config.cornerRadius.topLeft - config.cornerRadius.topRight,
					f32(config.width.top),
					config.color,
				)
			}
			if config.width.bottom > 0 {
				draw_rect(
					bounds.x + config.cornerRadius.bottomLeft,
					bounds.y + bounds.height - f32(config.width.bottom),
					bounds.width -
					config.cornerRadius.bottomLeft -
					config.cornerRadius.bottomRight,
					f32(config.width.bottom),
					config.color,
				)
			}

			if config.cornerRadius.topLeft > 0 {
				draw_arc(
					bounds.x + config.cornerRadius.topLeft,
					bounds.y + config.cornerRadius.topLeft,
					config.cornerRadius.topLeft - f32(config.width.top),
					config.cornerRadius.topLeft,
					180,
					270,
					config.color,
				)
			}
			if config.cornerRadius.topRight > 0 {
				draw_arc(
					bounds.x + bounds.width - config.cornerRadius.topRight,
					bounds.y + config.cornerRadius.topRight,
					config.cornerRadius.topRight - f32(config.width.top),
					config.cornerRadius.topRight,
					270,
					360,
					config.color,
				)
			}
			if config.cornerRadius.bottomLeft > 0 {
				draw_arc(
					bounds.x + config.cornerRadius.bottomLeft,
					bounds.y + bounds.height - config.cornerRadius.bottomLeft,
					config.cornerRadius.bottomLeft - f32(config.width.top),
					config.cornerRadius.bottomLeft,
					90,
					180,
					config.color,
				)
			}
			if config.cornerRadius.bottomRight > 0 {
				draw_arc(
					bounds.x + bounds.width - config.cornerRadius.bottomRight,
					bounds.y + bounds.height - config.cornerRadius.bottomRight,
					config.cornerRadius.bottomRight - f32(config.width.bottom),
					config.cornerRadius.bottomRight,
					0.1,
					90,
					config.color,
				)
			}
		case clay.RenderCommandType.Custom:
		}
	}
}

main :: proc() {
	min_mem_size := clay.MinMemorySize()
	memory := make([^]u8, min_mem_size)
	arena := clay.CreateArenaWithCapacityAndMemory(uint(min_mem_size), memory)

	clay.Initialize(
		arena,
		{cast(f32)raylib.GetScreenWidth(), cast(f32)raylib.GetScreenHeight()},
		{handler = error_handler},
	)
	clay.SetMeasureTextFunction(measure_text, nil)

	raylib.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .MSAA_4X_HINT})

	raylib.InitWindow(windowWidth, windowHeight, "Liteman")
	raylib.SetTargetFPS(raylib.GetMonitorRefreshRate(0))

	// Set window icon
	cwd := os.get_current_directory()
	defer delete(cwd)

	icon_path_str := fmt.tprintf("%s/resources/liteman.png", cwd)
	icon_path_cstr := strings.clone_to_cstring(icon_path_str, context.temp_allocator)

	if raylib.FileExists(icon_path_cstr) {
		icon_img := raylib.LoadImage(icon_path_cstr)
		if icon_img.data != nil {
			raylib.SetWindowIcon(icon_img)
			raylib.UnloadImage(icon_img)
		}
	}

	// Try to load system font, fallback to default if not found
	// We load at a large size (64) to ensure high quality when scaled down
	font_size: i32 = 64

	candidates := get_system_fonts()
	found_system_font := false
	font_path: cstring = "" // No bundled fallback

	for candidate in candidates {
		candidate_cstr := strings.clone_to_cstring(candidate, context.temp_allocator)
		if raylib.FileExists(candidate_cstr) {
			font_path = candidate_cstr
			found_system_font = true
			raylib.TraceLog(.INFO, "FONT: Using system font: %s", candidate_cstr)
			break
		}
	}

	if found_system_font {
		g_font = raylib.LoadFontEx(font_path, font_size, nil, 0)
	} else {
		raylib.TraceLog(.WARNING, "FONT: System font not found, using default Raylib font")
		g_font = raylib.GetFontDefault()
	}

	// Set bilinear filter for smoother scaling
	raylib.SetTextureFilter(g_font.texture, raylib.TextureFilter.BILINEAR)


	allocator := context.temp_allocator

	// Initialize app state
	app_state = init_app_state()
	load_state_commands(&app_state)
	defer destroy_app_state(&app_state)

	for !raylib.WindowShouldClose() {
		defer free_all(allocator)

		windowWidth = raylib.GetScreenWidth()
		windowHeight = raylib.GetScreenHeight()

		clay.SetLayoutDimensions(
			{cast(f32)raylib.GetScreenWidth(), cast(f32)raylib.GetScreenHeight()},
		)
		clay.SetPointerState(
			transmute(clay.Vector2)raylib.GetMousePosition(),
			raylib.IsMouseButtonDown(raylib.MouseButton.LEFT),
		)
		clay.UpdateScrollContainers(
			false,
			transmute(clay.Vector2)raylib.GetMouseWheelMoveV(),
			raylib.GetFrameTime(),
		)

		handle_interactions()

		// Check worker thread
		if app_state.worker_thread != nil {
			if thread.is_done(app_state.worker_thread) {
				thread.join(app_state.worker_thread)
				thread.destroy(app_state.worker_thread)
				app_state.worker_thread = nil

				sync.mutex_lock(&app_state.worker_mutex)
				if res, ok := app_state.worker_result.?; ok {
					if res.success {
						app_state.response_headers = res.headers
						app_state.response_body = res.body
						app_state.status_code = res.status_code
						app_state.request_state = .Success
					} else {
						app_state.error_message = res.error_msg
						app_state.request_state = .Error
					}
					// Clear result container? technically overwriting next time is fine,
					// but setting to nil implies handled.
					app_state.worker_result = nil
				}
				sync.mutex_unlock(&app_state.worker_mutex)
			}
		}

		// Update cursor blink timer
		app_state.cursor_blink_timer += raylib.GetFrameTime()
		if app_state.cursor_blink_timer > 1.0 {
			app_state.cursor_blink_timer = 0
		}

		render_commands := create_layout()
		// Rendering
		raylib.BeginDrawing()
		raylib.ClearBackground(clay_color_to_rl_color(COLOR_SIDEBAR))
		clay_raylib_render(&render_commands)

		// Draw custom folder icons
		// Draw custom folder icons (only if not searching, as search view is flat)
		if app_state.search_len == 0 {
			draw_folder_icons_recursive(&app_state.commands)
		}

		// Draw cursor for focused input
		draw_text_cursor()

		// Drag Ghost Rendering
		if app_state.is_dragging {
			mouse_pos := raylib.GetMousePosition()
			// Simple ghost rectangle
			raylib.DrawRectangle(
				cast(i32)mouse_pos.x + 10,
				cast(i32)mouse_pos.y + 10,
				150,
				30,
				clay_color_to_rl_color({80, 80, 90, 200}),
			)
			raylib.DrawText(
				"Moving...",
				cast(i32)mouse_pos.x + 20,
				cast(i32)mouse_pos.y + 18,
				20,
				raylib.WHITE,
			)
		}

		raylib.EndDrawing()
	}
}

// Basic syntax highlighting for JSON
render_highlighted_json :: proc(json_str: string) {
	if len(json_str) == 0 {return}

	// Colors
	COLOR_KEY :: clay.Color{100, 180, 240, 255} // Blue
	COLOR_STRING :: clay.Color{150, 200, 100, 255} // Green
	COLOR_NUMBER :: clay.Color{230, 150, 100, 255} // Orange
	COLOR_BOOL :: clay.Color{200, 100, 200, 255} // Purple
	COLOR_PUNCT :: clay.Color{200, 200, 200, 255} // Light Gray

	// Process line by line to ensure correct layout
	lines := strings.split(json_str, "\n")
	defer delete(lines)

	for line in lines {
		// Use a horizontal container for each line
		if clay.UI()(
		{
			layout = {
				layoutDirection = .LeftToRight,
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFit({})},
				childGap = 0, // No gap between tokens in a line
			},
		},
		) {
			// Tokenize the line
			in_string := false
			current_token_start := 0

			i := 0
			for i < len(line) {
				char := line[i]

				if in_string {
					if char == '"' && (i == 0 || line[i - 1] != '\\') {
						in_string = false

						// Check if it's a key (look ahead for colon)
						j := i + 1
						is_key_token := false
						for j < len(line) {
							if line[j] == ' ' || line[j] == '\t' || line[j] == '\r' {
								j += 1
								continue
							}
							if line[j] == ':' {
								is_key_token = true
							}
							break
						}

						color := is_key_token ? COLOR_KEY : COLOR_STRING

						// Render string token
						token := line[current_token_start:i + 1]
						clay.TextDynamic(
							token,
							clay.TextConfig(
								{textColor = color, fontSize = 18, fontId = FONT_ID_BODY_18},
							),
						)

						current_token_start = i + 1
					}
					i += 1
					continue
				}

				switch char {
				case '"':
					// Flush previous
					if i > current_token_start {
						token := line[current_token_start:i]
						clay.TextDynamic(
							token,
							clay.TextConfig(
								{textColor = COLOR_PUNCT, fontSize = 18, fontId = FONT_ID_BODY_18},
							),
						)
					}
					current_token_start = i
					in_string = true
					i += 1

				case '{', '}', '[', ']', ',', ':':
					// Flush previous
					if i > current_token_start {
						token := line[current_token_start:i]
						// Check keyword
						color := COLOR_NUMBER
						if token == "true" || token == "false" || token == "null" {
							color = COLOR_BOOL
						} else if strings.trim_space(token) == "" {
							color = COLOR_PUNCT
						}

						clay.TextDynamic(
							token,
							clay.TextConfig(
								{textColor = color, fontSize = 18, fontId = FONT_ID_BODY_18},
							),
						)
					}

					// Render punctuation
					token := line[i:i + 1]
					clay.TextDynamic(
						token,
						clay.TextConfig(
							{textColor = COLOR_PUNCT, fontSize = 18, fontId = FONT_ID_BODY_18},
						),
					)

					current_token_start = i + 1
					i += 1

				case ' ', '\t', '\r':
					i += 1

				case:
					i += 1
				}
			}

			// Flush remaining in line
			if current_token_start < len(line) {
				token := line[current_token_start:]
				// Check keyword
				color := COLOR_NUMBER
				if token == "true" || token == "false" || token == "null" {
					color = COLOR_BOOL
				} else if strings.trim_space(token) == "" {
					color = COLOR_PUNCT
				}

				clay.TextDynamic(
					token,
					clay.TextConfig({textColor = color, fontSize = 18, fontId = FONT_ID_BODY_18}),
				)
			}
		}
	}
}

// Get list of potential system fonts based on OS
get_system_fonts :: proc() -> []string {
	when ODIN_OS == .Windows {
		@(static) candidates := [?]string {
			"C:/Windows/Fonts/segoeui.ttf",
			"C:/Windows/Fonts/arial.ttf",
		}
		return candidates[:]
	} else when ODIN_OS == .Darwin {
		@(static) candidates := [?]string {
			"/System/Library/Fonts/SFNS.ttf",
			"/System/Library/Fonts/HelveticaNeue.ttf",
			"/Library/Fonts/Arial.ttf",
		}
		return candidates[:]
	} else when ODIN_OS == .Linux {
		@(static) candidates := [?]string {
			"/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf",
			"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
			"/usr/share/fonts/liberation/LiberationSans-Regular.ttf",
			"/usr/share/fonts/TTF/DejaVuSans.ttf", // Arch Linux
		}
		return candidates[:]
	} else {
		return []string{}
	}
}

// Helper to draw folder icons
draw_folder_icons_recursive :: proc(commands: ^[dynamic]SavedCommand) {
	for &cmd in commands {
		if cmd.type == .Folder {
			// Get layout info
			data := clay.GetElementData(clay.ID("FolderToggle", cmd.id))
			if data.found {
				// Draw based on state
				center := raylib.Vector2 {
					data.boundingBox.x + data.boundingBox.width / 2,
					data.boundingBox.y + data.boundingBox.height / 2,
				}

				// Size of the icon
				size: f32 = 10.0

				color := clay_color_to_rl_color(COLOR_TEXT_DIM)
				if clay.PointerOver(clay.ID("FolderToggle", cmd.id)) {
					color = clay_color_to_rl_color(COLOR_ACCENT)
				}

				if cmd.expanded {
					// Down Triangle (v) - CCW Order: Top Right -> Top Left -> Bottom
					raylib.DrawTriangle(
						{center.x + size / 2, center.y - size / 2}, // Top Right
						{center.x - size / 2, center.y - size / 2}, // Top Left
						{center.x, center.y + size / 2}, // Bottom
						color,
					)
				} else {
					// Right Triangle (>) - CCW Order: Top Left -> Bottom Left -> Right
					raylib.DrawTriangle(
						{center.x - size / 3, center.y - size / 2}, // Top Left
						{center.x - size / 3, center.y + size / 2}, // Bottom Left
						{center.x + size / 2, center.y}, // Right
						color,
					)
				}
			}

			if cmd.expanded {
				draw_folder_icons_recursive(&cmd.children)
			}
		}
	}
}
