package main

import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:strings"
import "core:encoding/json"
import "vendor:raylib"

// Constants for window and UI
WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 600
MAX_CURL_INPUT :: 1024
MAX_RESPONSE :: 10 * 1024 // 10KB response buffer
SAVE_FILE :: "saved_curl_commands.json"

// Command structure for saving
Command :: struct {
    name: string,
    curl: string,
}

// App state
AppState :: struct {
    curl_input: [MAX_CURL_INPUT]u8,
    response: [MAX_RESPONSE]u8,
    response_scroll: i32,
    saved_commands: [dynamic]Command,
    selected_command: i32,
    edit_mode: bool,
    edit_name_buffer: [256]u8,
    error_msg: string,
}

// Global state
state: AppState

// Load saved commands from JSON file
load_commands :: proc() {
    data, ok := os.read_entire_file(SAVE_FILE)
    if !ok {
        state.error_msg = "Failed to load saved commands"
        return
    }
    defer delete(data)
    err := json.unmarshal(data, &state.saved_commands)
    if err != nil {
        state.error_msg = "Failed to parse saved commands"
    }
}

// Save commands to JSON file
save_commands :: proc() {
    data, err := json.marshal(state.saved_commands)
    if err != nil {
        state.error_msg = "Failed to serialize commands"
        return
    }
    defer delete(data)
    ok := os.write_entire_file(SAVE_FILE, data)
    if !ok {
        state.error_msg = "Failed to save commands"
    }
}

// Run cURL command via system shell
run_curl :: proc(cmd: string) {
    full_cmd := strings.concatenate({"curl ", cmd})
    defer delete(full_cmd)
    
    r, w, pipe_err := os2.pipe()
    if pipe_err != nil {
        state.error_msg = "Failed to create pipe"
        return
    }
    defer os2.close(r)
    defer os2.close(w)
    
    process, proc_err := os2.process_start(os2.Process_Desc{"curl", {cmd}, nil, nil,w,r})
    if proc_err != nil {
        state.error_msg = "Failed to run cURL"
        return
    }
    
    buffer: [MAX_RESPONSE]u8
    bytes_read, read_err := os.read(os.stdin, buffer[:])
    if read_err != nil {
        state.error_msg = "Failed to read cURL output"
        return
    }
    
    // Try to parse as JSON for pretty printing
    json_data: json.Value
    parse_err := json.unmarshal(buffer[:bytes_read], &json_data)
    if parse_err == nil {
        formatted, fmt_err := json.marshal(json_data, {pretty = true})
        if fmt_err == nil {
            copy(state.response[:], formatted)
            delete(formatted)
        } else {
            copy(state.response[:], buffer[:bytes_read])
        }
        json.destroy_value(json_data)
    } else {
        copy(state.response[:], buffer[:bytes_read])
    }
    state.response_scroll = 0
}

// Main setup
setup :: proc() {
    raylib.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "cURL Command Runner")
    raylib.SetTargetFPS(60)
    state = AppState{
        curl_input = {},
        response = {},
        response_scroll = 0,
        saved_commands = make([dynamic]Command),
        selected_command = -1,
        edit_mode = false,
        edit_name_buffer = {},
        error_msg = "",
    }
    load_commands()
}

// Main loop
main :: proc() {
    setup()
    defer raylib.CloseWindow()
    defer delete(state.saved_commands)
    
    for !raylib.WindowShouldClose() {
        // Input box for cURL command
        raylib.BeginDrawing()
        raylib.ClearBackground(raylib.RAYWHITE)
        
        raylib.GuiLabel(raylib.Rectangle{10, 10, 100, 30}, "cURL Command:")
        if raylib.GuiTextBox(raylib.Rectangle{120, 10, 670, 30}, fmt.caprintf(string(state.curl_input[:])), MAX_CURL_INPUT, true) {
            // Input changed
        }
        
        // Buttons: Run, Save, Copy
        if raylib.GuiButton(raylib.Rectangle{120, 50, 100, 30}, "Run") {
            cmd := strings.trim_space(string(state.curl_input[:]))
            if len(cmd) > 0 {
                run_curl(cmd)
            } else {
                state.error_msg = "Please enter a cURL command"
            }
        }
        if raylib.GuiButton(raylib.Rectangle{230, 50, 100, 30}, "Copy Response") {
            raylib.SetClipboardText(fmt.caprintf(string(state.response[:])))
        }
        if raylib.GuiButton(raylib.Rectangle{340, 50, 100, 30}, "Save Command") {
            cmd := strings.trim_space(string(state.curl_input[:]))
            if len(cmd) > 0 {
                state.edit_mode = true
                state.edit_name_buffer = {}
            } else {
                state.error_msg = "Please enter a cURL command to save"
            }
        }
        
        // Saved commands list
        raylib.GuiLabel(raylib.Rectangle{10, 90, 100, 30}, "Saved Commands:")

        _cmds := make([dynamic]string)
        for cmd in state.saved_commands {
            append(&_cmds, cmd.name)
        }
        selected := raylib.GuiListView(raylib.Rectangle{120, 90, 670, 150}, 
            fmt.caprintf(strings.join({"test1", "test2"}, ";")), 
            &state.response_scroll, &state.selected_command)
        if selected != state.selected_command && selected >= 0 && int(selected) < len(state.saved_commands) {
            state.selected_command = selected
            copy(state.curl_input[:], state.saved_commands[selected].curl)
        }
        
        // Edit/Delete buttons for saved commands
        if state.selected_command >= 0 && int(state.selected_command) < len(state.saved_commands) {
            if raylib.GuiButton(raylib.Rectangle{120, 250, 100, 30}, "Edit Name") {
                state.edit_mode = true
                copy(state.edit_name_buffer[:], state.saved_commands[state.selected_command].name)
            }
            if raylib.GuiButton(raylib.Rectangle{230, 250, 100, 30}, "Delete") {
                ordered_remove(&state.saved_commands, state.selected_command)
                save_commands()
                state.selected_command = -1
            }
        }
        
        // Edit name popup
        if state.edit_mode {
            raylib.GuiLabel(raylib.Rectangle{120, 290, 100, 30}, "Command Name:")
            if raylib.GuiTextBox(raylib.Rectangle{230, 290, 300, 30}, "state.edit_name_buffer[:]", 256, true) {
                // Name input changed
            }
            if raylib.GuiButton(raylib.Rectangle{540, 290, 100, 30}, "Save") {
                name := strings.trim_space(string(state.edit_name_buffer[:]))
                if len(name) > 0 {
                    if state.selected_command >= 0 && int(state.selected_command) < len(state.saved_commands) {
                        // Edit existing
                        state.saved_commands[state.selected_command].name = strings.clone(name)
                    } else {
                        // New command
                        cmd := strings.clone(strings.trim_space(string(state.curl_input[:])))
                        append(&state.saved_commands, Command{name = strings.clone(name), curl = cmd})
                    }
                    save_commands()
                    state.edit_mode = false
                } else {
                    state.error_msg = "Please enter a command name"
                }
            }
            if raylib.GuiButton(raylib.Rectangle{650, 290, 100, 30}, "Cancel") {
                state.edit_mode = false
            }
        }
        
        // Response display
        raylib.GuiLabel(raylib.Rectangle{10, 330, 100, 30}, "Response:")
        raylib.GuiTextBox(raylib.Rectangle{120, 330, 670, 250}, "state.response[:]", MAX_RESPONSE, false)
        
        // Error message
        if len(state.error_msg) > 0 {
            raylib.GuiLabel(raylib.Rectangle{10, 590, 780, 30}, strings.clone_to_cstring(state.error_msg))
        }
        
        raylib.EndDrawing()
    }
}
