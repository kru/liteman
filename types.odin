package main

SavedCommand :: struct {
	id:      u32,
	name:    string,
	command: string,
}

RequestState :: enum {
	Idle,
	Loading,
	Success,
	Error,
}

AppState :: struct {
	// Saved commands
	commands:                         [dynamic]SavedCommand,
	next_id:                          u32,

	// UI state - Search
	search_text:                      [256]u8,
	search_len:                       int,
	search_cursor:                    int,
	search_sel_anchor:                Maybe(int), // Selection anchor (nil = no selection)

	// UI state - cURL input
	curl_input:                       [32768]u8, // 32 KiB
	curl_input_len:                   int,
	curl_cursor:                      int,
	curl_sel_anchor:                  Maybe(int), // Selection anchor (nil = no selection)

	// UI state - Command name input (for saving)
	name_input:                       [256]u8,
	name_input_len:                   int,
	name_cursor:                      int,
	name_sel_anchor:                  Maybe(int), // Selection anchor (nil = no selection)

	// Cursor blink timer
	cursor_blink_timer:               f32,

	// Response
	response_headers:                 string,
	response_body:                    string,
	status_code:                      int,
	request_state:                    RequestState,
	error_message:                    string,
	active_tab:                       ResponseTab,

	// Selection
	selected_id:                      Maybe(u32),
	editing_id:                       Maybe(u32),

	// Scrollbar drag state
	scrollbar_dragging:               bool,
	scrollbar_drag_start_y:           f32,
	scrollbar_scroll_start_y:         f32,

	// Sidebar scrollbar drag state
	sidebar_scrollbar_dragging:       bool,
	sidebar_scrollbar_drag_start_y:   f32,
	sidebar_scrollbar_scroll_start_y: f32,
}

ResponseTab :: enum {
	Body,
	Headers,
}

// Initialize app state with defaults
init_app_state :: proc() -> AppState {
	return AppState{commands = make([dynamic]SavedCommand), next_id = 1, request_state = .Idle}
}

// Cleanup app state
destroy_app_state :: proc(state: ^AppState) {
	for &cmd in state.commands {
		delete(cmd.name)
		delete(cmd.command)
	}
	delete(state.commands)

	if len(state.response_headers) > 0 {
		delete(state.response_headers)
	}
	if len(state.response_body) > 0 {
		delete(state.response_body)
	}
	if len(state.error_message) > 0 {
		delete(state.error_message)
	}
}
