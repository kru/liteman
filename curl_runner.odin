package main

import "core:encoding/json"
import "core:os/os2"
import "core:strconv"
import "core:strings"

// Result from running a cURL command
// Result from running a cURL command
CurlResult :: struct {
	headers:     string,
	body:        string,
	status_code: int,
	error_msg:   string,
	success:     bool,
}

// Run cURL command via shell and capture output
run_curl :: proc(command: string) -> CurlResult {
	result := CurlResult {
		status_code = 0,
		success     = false,
	}

	// Validate command starts with "curl"
	// Preprocess to handle multi-line commands (remove backslash + newline)
	// Replace both \r\n and \n to be safe
	sanitized_command, _ := strings.replace_all(command, "\\\r\n", " ", context.temp_allocator)
	sanitized_command, _ = strings.replace_all(
		sanitized_command,
		"\\\n",
		" ",
		context.temp_allocator,
	)

	trimmed := strings.trim_space(sanitized_command)
	if !strings.has_prefix(trimmed, "curl") {
		result.error_msg = strings.clone("Command must start with 'curl'")
		return result
	}

	// Add -i flag if not present to get headers (for status code)
	// Add -s flag to suppress progress meter
	modified_cmd := sanitized_command
	needs_free := false

	if !strings.contains(sanitized_command, " -i") &&
	   !strings.contains(sanitized_command, " -i ") {
		modified_cmd = strings.concatenate({sanitized_command, " -i -s"})
		needs_free = true
	} else if !strings.contains(sanitized_command, " -s") {
		modified_cmd = strings.concatenate({sanitized_command, " -s"})
		needs_free = true
	}
	defer if needs_free {
		delete(modified_cmd)
	}

	// Execute the command using os2.process_exec
	stdout_str: string
	stderr_str: string

	when ODIN_OS == .Windows {
		// Windows: use curl.exe directly with arguments
		// First, extract arguments from the curl command
		curl_args := make([dynamic]string)
		defer delete(curl_args)

		// Start with curl.exe
		append(&curl_args, "curl.exe")

		// Parse the command to extract arguments (skip "curl" at start)
		cmd_without_curl := strings.trim_prefix(strings.trim_space(modified_cmd), "curl")
		cmd_without_curl = strings.trim_space(cmd_without_curl)

		// Argument parsing - split by spaces but respect both single and double quotes
		quote_char: rune = 0 // 0 = not in quotes, otherwise the quote character
		current_arg := strings.builder_make()
		defer strings.builder_destroy(&current_arg)

		for c in cmd_without_curl {
			if quote_char == 0 {
				// Not in quotes
				if c == '"' || c == '\'' {
					quote_char = c // Start quoted section
				} else if c == ' ' {
					arg := strings.to_string(current_arg)
					if len(arg) > 0 {
						// Escape double quotes for Windows command line
						safe_arg := strings.clone(arg, context.temp_allocator)
						append(&curl_args, safe_arg)
					}
					strings.builder_reset(&current_arg)
				} else {
					strings.write_rune(&current_arg, c)
				}
			} else {
				// In quotes
				if c == quote_char {
					quote_char = 0 // End quoted section
				} else {
					strings.write_rune(&current_arg, c)
				}
			}
		}
		// Don't forget the last argument
		last_arg := strings.to_string(current_arg)
		if len(last_arg) > 0 {
			// Escape double quotes for Windows command line
			safe_arg := strings.clone(last_arg, context.temp_allocator)
			append(&curl_args, safe_arg)
		}

		state, stdout, stderr, err := os2.process_exec({command = curl_args[:]}, context.allocator)
		defer delete(stdout)
		defer delete(stderr)

		if err != nil {
			result.error_msg = strings.clone("Failed to execute command")
			return result
		}

		stdout_str = string(stdout)
		stderr_str = string(stderr)
	} else {
		// Unix: use sh -c
		state, stdout, stderr, err := os2.process_exec(
			{command = {"/bin/sh", "-c", modified_cmd}},
			context.allocator,
		)
		defer delete(stdout)
		defer delete(stderr)

		if err != nil {
			result.error_msg = strings.clone("Failed to execute command")
			return result
		}

		stdout_str = string(stdout)
		stderr_str = string(stderr)
	}

	if stdout_str == "" {
		if stderr_str != "" {
			result.error_msg = strings.clone(stderr_str)
		} else {
			result.error_msg = strings.clone("No response received")
		}
		return result
	}

	// Split headers and body
	// find "\r\n\r\n" or "\n\n"
	header_end := -1
	body_start := -1

	if idx := strings.index(stdout_str, "\r\n\r\n"); idx >= 0 {
		header_end = idx
		body_start = idx + 4
	} else if idx := strings.index(stdout_str, "\n\n"); idx >= 0 {
		header_end = idx
		body_start = idx + 2
	}

	if header_end >= 0 {
		result.headers = strings.clone(stdout_str[:header_end])
		body_raw := stdout_str[body_start:]

		// Try to format JSON
		if strings.has_prefix(strings.trim_space(body_raw), "{") ||
		   strings.has_prefix(strings.trim_space(body_raw), "[") {

			// Parse JSON
			json_data, err := json.parse_string(body_raw, json.DEFAULT_SPECIFICATION, true)
			if err == nil {
				defer json.destroy_value(json_data)

				// Marshal with indentation
				opt := json.Marshal_Options {
					pretty     = true,
					use_spaces = true,
					spaces     = 2,
				}

				if formatted, err := json.marshal(json_data, opt); err == nil {
					result.body = string(formatted)
				} else {
					result.body = strings.clone(body_raw)
				}
			} else {
				result.body = strings.clone(body_raw)
			}
		} else {
			result.body = strings.clone(body_raw)
		}
	} else {
		// Assume all body or all headers? curl -i ensures headers, so likely execution error or simple output
		result.body = strings.clone(stdout_str)
	}

	result.status_code = parse_status_code(result.headers != "" ? result.headers : result.body)
	result.success = true

	return result
}

// Parse HTTP status code from response headers
parse_status_code :: proc(response: string) -> int {
	// Look for "HTTP/1.1 XXX" or "HTTP/2 XXX" pattern
	lines := strings.split_lines(response)
	defer delete(lines)

	for line in lines {
		if strings.has_prefix(line, "HTTP/") {
			// Find the status code (3 digits after HTTP/X.X or HTTP/X)
			parts := strings.split(line, " ")
			defer delete(parts)

			if len(parts) >= 2 {
				code, ok := strconv.parse_int(parts[1])
				if ok {
					return code
				}
			}
		}
	}

	return 0 // Unknown status
}

// Free curl result resources
free_curl_result :: proc(result: ^CurlResult) {
	if len(result.headers) > 0 {
		delete(result.headers)
		result.headers = ""
	}
	if len(result.body) > 0 {
		delete(result.body)
		result.body = ""
	}
	if len(result.error_msg) > 0 {
		delete(result.error_msg)
		result.error_msg = ""
	}
}
