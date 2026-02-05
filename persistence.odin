package main

import "core:encoding/json"
import "core:os"
import "core:strings"

COMMANDS_FILE :: "commands.json"

// JSON-serializable version of SavedCommand
SavedCommandJson :: struct {
	id:      u32,
	name:    string,
	command: string,
}

// Save commands to JSON file
save_commands :: proc(commands: []SavedCommand) -> bool {
	json_commands := make([dynamic]SavedCommandJson, len(commands))
	defer delete(json_commands)

	for cmd, i in commands {
		json_commands[i] = SavedCommandJson {
			id      = cmd.id,
			name    = cmd.name,
			command = cmd.command,
		}
	}

	data, err := json.marshal(json_commands[:])
	if err != nil {
		return false
	}
	defer delete(data)

	return os.write_entire_file(COMMANDS_FILE, data)
}

// Load commands from JSON file
load_commands :: proc() -> ([dynamic]SavedCommand, bool) {
	commands := make([dynamic]SavedCommand)

	data, ok := os.read_entire_file(COMMANDS_FILE)
	if !ok {
		// File doesn't exist yet, return empty list
		return commands, true
	}
	defer delete(data)

	json_commands: [dynamic]SavedCommandJson
	defer delete(json_commands)

	err := json.unmarshal(data, &json_commands)
	if err != nil {
		return commands, false
	}

	for jcmd in json_commands {
		append(
			&commands,
			SavedCommand {
				id = jcmd.id,
				name = strings.clone(jcmd.name),
				command = strings.clone(jcmd.command),
			},
		)
	}

	return commands, true
}

// Get the next available ID based on existing commands
get_next_id :: proc(commands: []SavedCommand) -> u32 {
	max_id: u32 = 0
	for cmd in commands {
		if cmd.id > max_id {
			max_id = cmd.id
		}
	}
	return max_id + 1
}

// Add a new command
add_command :: proc(state: ^AppState, name: string, command: string) {
	new_cmd := SavedCommand {
		id      = state.next_id,
		name    = strings.clone(name),
		command = strings.clone(command),
	}
	append(&state.commands, new_cmd)
	state.next_id += 1
	save_commands(state.commands[:])
}

// Delete a command by ID
delete_command :: proc(state: ^AppState, id: u32) {
	for cmd, i in state.commands {
		if cmd.id == id {
			delete(cmd.name)
			delete(cmd.command)
			ordered_remove(&state.commands, i)
			save_commands(state.commands[:])
			return
		}
	}
}

// Update a command
update_command :: proc(state: ^AppState, id: u32, name: string, command: string) {
	for &cmd in state.commands {
		if cmd.id == id {
			delete(cmd.name)
			delete(cmd.command)
			cmd.name = strings.clone(name)
			cmd.command = strings.clone(command)
			save_commands(state.commands[:])
			return
		}
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
