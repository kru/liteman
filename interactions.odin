package main

import clay "clay-odin"
import "core:strings"
import "vendor:raylib"

// Helper to check interactions recursively
check_command_interactions :: proc(commands: ^[dynamic]SavedCommand) -> bool {
	for &cmd in commands {
		// Folder Toggle click
		if cmd.type == .Folder {
			if clay.PointerOver(clay.ID("FolderToggle", cmd.id)) {
				if raylib.IsMouseButtonPressed(.LEFT) {
					cmd.expanded = !cmd.expanded
					return true
				}
			}
		}

		// Edit button click
		if clay.PointerOver(clay.ID("EditBtn", cmd.id)) {
			if raylib.IsMouseButtonPressed(.LEFT) {
				start_editing_command(&cmd)
				return true
			}
		}

		// Delete button click
		if clay.PointerOver(clay.ID("DelBtn", cmd.id)) {
			if raylib.IsMouseButtonPressed(.LEFT) {
				delete_command(&app_state, cmd.id)
				app_state.selected_id = nil
				return true
			}
		}

		// Save name button click (when editing)
		if clay.PointerOver(clay.ID("SaveNameBtn", cmd.id)) {
			if raylib.IsMouseButtonPressed(.LEFT) {
				save_editing_command()
				return true
			}
		}

		// Check for clicks on the command name (when editing)
		if editing_id, ok := app_state.editing_id.?; ok && editing_id == cmd.id {
			if clay.PointerOver(clay.ID("CmdName", cmd.id)) {
				bounds_data := clay.GetElementData(clay.ID("CmdName", cmd.id))
				if bounds_data.found {
					mouse_x := raylib.GetMousePosition().x
					// mouse_y := raylib.GetMousePosition().y // unused

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

		// Drag/Drop and Selection Logic
		if clay.PointerOver(clay.ID("CmdItem", cmd.id)) {
			// 1. Drop Logic (if already dragging)
			if app_state.is_dragging {
				if dragging_id, ok := app_state.dragging_id.?; ok && dragging_id != cmd.id {
					// Drop on Folder
					if cmd.type == .Folder {
						if raylib.IsMouseButtonReleased(.LEFT) {
							move_command(&app_state, dragging_id, cmd.id)
							app_state.dragging_id = nil
							app_state.is_dragging = false
							return true
						}
					}
				}
			} else {
				// 2. Start Drag / Select Logic (if not dragging)
				if raylib.IsMouseButtonPressed(.LEFT) {
					// Only select/drag if not clicking buttons
					is_editing := false
					if eid, ok := app_state.editing_id.?; ok && eid == cmd.id {
						is_editing = true
					}

					is_toggle := false
					if cmd.type == .Folder {
						if clay.PointerOver(clay.ID("FolderToggle", cmd.id)) {
							is_toggle = true
						}
					}

					clicked_name_while_editing :=
						is_editing && clay.PointerOver(clay.ID("CmdName", cmd.id))

					if !clay.PointerOver(clay.ID("EditBtn", cmd.id)) &&
					   !clay.PointerOver(clay.ID("DelBtn", cmd.id)) &&
					   !clay.PointerOver(clay.ID("SaveNameBtn", cmd.id)) &&
					   !clicked_name_while_editing &&
					   !is_toggle {

						// Start Potential Drag
						app_state.dragging_id = cmd.id
						app_state.drag_start_pos = raylib.GetMousePosition()
						app_state.is_dragging = false // Will be set to true if moved

						// Also Select
						if cmd.type == .Folder {
							app_state.selected_id = cmd.id
						} else {
							load_command(&cmd)
						}
						return true
					}
				}
			}
		}

		// Check children
		if cmd.type == .Folder && cmd.expanded {
			if check_command_interactions(&cmd.children) {
				return true
			}
		}
	}
	return false
}

// Handle click interactions
handle_interactions :: proc() {
	// 1. Check specific item interactions first
	item_handled := check_command_interactions(&app_state.commands)

	// 2. Check Global Drag Logic (if not handled by item)
	if dragging_id, ok := app_state.dragging_id.?; ok {
		// Check for drag threshold
		if !app_state.is_dragging {
			if raylib.IsMouseButtonDown(.LEFT) {
				// Manual vector subtraction
				current_pos := raylib.GetMousePosition()
				delta_x := current_pos.x - app_state.drag_start_pos.x
				delta_y := current_pos.y - app_state.drag_start_pos.y

				// Length squared check is faster, 5*5 = 25
				if (delta_x * delta_x + delta_y * delta_y) > 25.0 {
					app_state.is_dragging = true
				}
			} else {
				// Mouse released before drag threshold -> just a click (already handled as selection)
				// Only clear if not handled by item (though item click would have returned true)
				if !item_handled {
					app_state.dragging_id = nil
				}
			}
		} else {
			// Already dragging
			// Only process global drop if item didn't handle it
			if !item_handled && raylib.IsMouseButtonReleased(.LEFT) {
				// Mouse Up while dragging
				// If we are here, it means we didn't drop on a specific folder (handled in check_command_interactions)
				// So check if we dropped on sidebar (Move to Root)

				if clay.PointerOver(clay.ID("Sidebar")) {
					move_command(&app_state, dragging_id, 0)
				}

				// Logic for canceling drag if dropped elsewhere
				app_state.dragging_id = nil
				app_state.is_dragging = false
			}
		}
	}


	// Check New Request button
	if clay.PointerOver(clay.ID("NewRequestBtn")) {
		if raylib.IsMouseButtonPressed(.LEFT) {
			app_state.selected_id = nil
			app_state.editing_id = nil
			editor_set_text(&app_state.curl_editor, "curl https://example.com")
			focused_input = .CurlInput
		}
	}

	// Check New Folder button
	if clay.PointerOver(clay.ID("NewFolderBtn")) {
		if raylib.IsMouseButtonPressed(.LEFT) {
			add_folder_root(&app_state, "New Folder")
		}
	}

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
			execute_curl_command()
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

	// Check command interactions (recursive)


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
			cursor_x := calculate_text_width(
				app_state.name_input[:],
				app_state.name_cursor,
				FONT_ID_BODY_18,
			)

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
			// Don't unfocus if focused on NameInput (it has its own save/cancel logic usually, but here checking bounds helps)
			if focused_input != .NameInput {
				focused_input = .None
			}
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
					// Thumb height proportional to visible area
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
