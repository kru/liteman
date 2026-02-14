package main

import "core:sync"
import "core:thread"
import "vendor:raylib"

CommandType :: enum {
	Request,
	Folder,
}

SavedCommand :: struct {
	id:       u32,
	type:     CommandType,
	name:     string,
	command:  string,
	children: [dynamic]SavedCommand,
	expanded: bool,
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

	// UI state - cURL editor
	curl_editor:                      Editor,

	// UI state - Command name input (for saving)
	name_input:                       [256]u8,
	name_input_len:                   int,
	name_cursor:                      int,
	name_sel_anchor:                  Maybe(int), // Selection anchor (nil = no selection)
	name_input_scroll_x:              f32, // Horizontal scroll offset for name input

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

	// Drag and Drop state
	dragging_id:                      Maybe(u32),
	drag_start_pos:                   raylib.Vector2,
	is_dragging:                      bool,

	// Threading state
	worker_thread:                    ^thread.Thread,
	worker_result:                    Maybe(CurlResult),
	worker_mutex:                     sync.Mutex,
}

ResponseTab :: enum {
	Body,
	Headers,
}

// Initialize app state with defaults
init_app_state :: proc() -> AppState {
	state := AppState {
		commands      = make([dynamic]SavedCommand),
		next_id       = 1,
		request_state = .Idle,
		curl_editor   = init_editor(),
	}
	return state
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

	destroy_editor(&state.curl_editor)

	if state.worker_thread != nil {
		thread.terminate(state.worker_thread, 1)
		thread.destroy(state.worker_thread)
	}
}
