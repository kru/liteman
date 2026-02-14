package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// Get the configuration directory for the application
get_config_dir :: proc() -> string {
	when ODIN_OS == .Windows {
		app_data := os.get_env("APPDATA", context.temp_allocator)
		if app_data != "" {
			return filepath.join({app_data, "Liteman"}, context.temp_allocator)
		}
	} else when ODIN_OS == .Darwin {
		home := os.get_env("HOME", context.temp_allocator)
		if home != "" {
			return filepath.join(
				{home, "Library", "Application Support", "Liteman"},
				context.temp_allocator,
			)
		}
	} else {
		home := os.get_env("HOME", context.temp_allocator)
		if home != "" {
			return filepath.join({home, ".config", "liteman"}, context.temp_allocator)
		}
	}
	return "."
}

get_commands_file_path :: proc() -> string {
	dir := get_config_dir()
	return filepath.join({dir, "commands.json"}, context.temp_allocator)
}

// JSON-serializable version of SavedCommand
SavedCommandJson :: struct {
	id:       u32,
	type:     CommandType,
	name:     string,
	command:  string,
	children: [dynamic]SavedCommandJson,
	expanded: bool,
}

// Convert core struct to JSON struct (recursive)
to_json_struct :: proc(cmd: SavedCommand) -> SavedCommandJson {
	json_cmd := SavedCommandJson {
		id       = cmd.id,
		type     = cmd.type,
		name     = cmd.name,
		command  = cmd.command,
		expanded = cmd.expanded,
	}

	if len(cmd.children) > 0 {
		json_cmd.children = make([dynamic]SavedCommandJson, len(cmd.children))
		for child, i in cmd.children {
			json_cmd.children[i] = to_json_struct(child)
		}
	}

	return json_cmd
}

// Convert JSON struct to core struct (recursive)
from_json_struct :: proc(jcmd: SavedCommandJson) -> SavedCommand {
	cmd := SavedCommand {
		id       = jcmd.id,
		type     = jcmd.type,
		name     = strings.clone(jcmd.name),
		command  = strings.clone(jcmd.command),
		expanded = jcmd.expanded,
	}

	if len(jcmd.children) > 0 {
		cmd.children = make([dynamic]SavedCommand)
		for child in jcmd.children {
			append(&cmd.children, from_json_struct(child))
		}
	}

	return cmd
}

// Helper to free JSON struct
destroy_json_struct :: proc(jcmd: SavedCommandJson) {
	// Strings in JSON struct might be slices into the original data if using strict unmarshal,
	// but here we are constructing them.
	// Since we use the default allocator for `to_json_struct`'s dynamic array, we should free it.
	// But strings are just copies/refs.
	// Actually `json.marshal` handles the allocation for the output string.
	// `to_json_struct` allocates the dynamic array.
	for child in jcmd.children {
		destroy_json_struct(child)
	}
	delete(jcmd.children)
}

// Save commands to JSON file
save_commands :: proc(commands: []SavedCommand, file_path: string = "") -> bool {
	json_commands := make([dynamic]SavedCommandJson, len(commands))
	defer {
		for cmd in json_commands {
			destroy_json_struct(cmd)
		}
		delete(json_commands)
	}

	for cmd, i in commands {
		json_commands[i] = to_json_struct(cmd)
	}

	// Marshal with pretty printing (indentation)
	opt := json.Marshal_Options {
		pretty = true,
	}

	data, err := json.marshal(json_commands[:], opt)
	if err != nil {
		fmt.println("Error marshalling commands:", err)
		return false
	}
	defer delete(data)

	path_to_use := file_path
	if path_to_use == "" {
		// Ensure config directory exists only when using default path
		config_dir := get_config_dir()
		if config_dir != "." && !os.exists(config_dir) {
			os.make_directory(config_dir)
		}
		path_to_use = get_commands_file_path()
	}

	return os.write_entire_file(path_to_use, data)
}

// Helper to free JSON struct deeply (including strings, for unmarshalled data)
destroy_decoded_json_struct :: proc(jcmd: SavedCommandJson) {
	delete(jcmd.name)
	delete(jcmd.command)
	for child in jcmd.children {
		destroy_decoded_json_struct(child)
	}
	delete(jcmd.children)
}

// Load commands from JSON file
load_commands :: proc(file_path: string = "") -> ([dynamic]SavedCommand, bool) {
	commands := make([dynamic]SavedCommand)

	path_to_use := file_path
	if path_to_use == "" {
		path_to_use = get_commands_file_path()
	}

	data, ok := os.read_entire_file(path_to_use)
	if !ok {
		// File doesn't exist yet, return empty list
		return commands, true
	}
	defer delete(data)

	// Check if file is empty
	if len(data) == 0 {
		return commands, true
	}

	json_commands: [dynamic]SavedCommandJson
	defer {
		for jcmd in json_commands {
			destroy_decoded_json_struct(jcmd)
		}
		delete(json_commands)
	}

	err := json.unmarshal(data, &json_commands)
	if err != nil {
		fmt.println("Error unmarshalling commands:", err)
		// Fallback for empty or corrupt file - return empty list logic handled above
		// If it fails, maybe legacy format?
		// For now we assume fresh start as requested.
		return commands, false
	}

	for jcmd in json_commands {
		append(&commands, from_json_struct(jcmd))
	}

	return commands, true
}

// Get the max ID recursively
get_max_id_recursive :: proc(commands: []SavedCommand) -> u32 {
	max_id: u32 = 0
	for cmd in commands {
		if cmd.id > max_id {
			max_id = cmd.id
		}
		if len(cmd.children) > 0 {
			child_max := get_max_id_recursive(cmd.children[:])
			if child_max > max_id {
				max_id = child_max
			}
		}
	}
	return max_id
}

// Get the next available ID
get_next_id :: proc(commands: []SavedCommand) -> u32 {
	return get_max_id_recursive(commands) + 1
}

// Add a new command to root
add_command_root :: proc(state: ^AppState, name: string, command: string) {
	new_cmd := SavedCommand {
		id      = state.next_id,
		type    = .Request,
		name    = strings.clone(name),
		command = strings.clone(command),
	}
	append(&state.commands, new_cmd)
	state.next_id += 1
	save_commands(state.commands[:])
}

// Add a new folder to root
add_folder_root :: proc(state: ^AppState, name: string) {
	new_cmd := SavedCommand {
		id       = state.next_id,
		type     = .Folder,
		name     = strings.clone(name),
		children = make([dynamic]SavedCommand),
		expanded = true,
	}
	append(&state.commands, new_cmd)
	state.next_id += 1
	save_commands(state.commands[:])
}

// Recursive delete helper
delete_command_recursive :: proc(commands: ^[dynamic]SavedCommand, id: u32) -> bool {
	for cmd, i in commands {
		if cmd.id == id {
			// Found it, free memory
			delete(cmd.name)
			delete(cmd.command)
			// Recursively free children
			free_children_recursive(cmd)
			ordered_remove(commands, i)
			return true
		}

		// Search children
		if len(cmd.children) > 0 {
			if delete_command_recursive(&commands[i].children, id) {
				return true
			}
		}
	}
	return false
}

free_children_recursive :: proc(cmd: SavedCommand) {
	for child in cmd.children {
		delete(child.name)
		delete(child.command)
		free_children_recursive(child)
	}
	delete(cmd.children)
}

// Delete a command by ID (searches recursively)
delete_command :: proc(state: ^AppState, id: u32) {
	if delete_command_recursive(&state.commands, id) {
		save_commands(state.commands[:])
	}
}

// Recursive update helper
update_command_recursive :: proc(
	commands: ^[dynamic]SavedCommand,
	id: u32,
	name: string,
	command: string,
) -> bool {
	for &cmd in commands {
		if cmd.id == id {
			delete(cmd.name)
			delete(cmd.command)
			cmd.name = strings.clone(name)
			cmd.command = strings.clone(command)
			return true
		}

		if len(cmd.children) > 0 {
			if update_command_recursive(&cmd.children, id, name, command) {
				return true
			}
		}
	}
	return false
}

// Update a command (searches recursively)
update_command :: proc(state: ^AppState, id: u32, name: string, command: string) {
	if update_command_recursive(&state.commands, id, name, command) {
		save_commands(state.commands[:])
	}
}

// Load saved commands into app state
load_state_commands :: proc(state: ^AppState) -> bool {
	commands, ok := load_commands()
	if !ok {
		return false
	}
	state.commands = commands
	state.next_id = get_next_id(commands[:])
	return true
}

// Find a command by ID (recursive)
find_command_recursive :: proc(commands: []SavedCommand, id: u32) -> ^SavedCommand {
	for &cmd in commands {
		if cmd.id == id {
			return &cmd
		}
		if len(cmd.children) > 0 {
			found := find_command_recursive(cmd.children[:], id)
			if found != nil {
				return found
			}
		}
	}
	return nil
}

// Helper to find command in state
find_command :: proc(state: ^AppState, id: u32) -> ^SavedCommand {
	return find_command_recursive(state.commands[:], id)
}
