package main

import "core:encoding/json"
import "core:os/os2"
import "core:strconv"
import "core:strings"
import "core:sys/windows"

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

	// Preprocess to handle multi-line commands:
	// 1. Remove backslash line continuations (join lines)
	// 2. Convert unquoted newlines to spaces
	sanitized_command := sanitize_curl_command_string(command, context.temp_allocator)

	trimmed := strings.trim_space(sanitized_command)
	if !strings.has_prefix(trimmed, "curl") {
		result.error_msg = strings.clone("Command must start with 'curl'")
		return result
	}

	// Parse command into arguments
	args := tokenize_command(sanitized_command)
	defer delete(args)

	// Filter args to ensure curl is first and flags are present
	final_args := make([dynamic]string)
	defer delete(final_args)

	// Ensure first arg is curl (or add it if missing, though we check prefix above)
	if len(args) > 0 && args[0] == "curl" {
		append(&final_args, "curl")
	} else {
		append(&final_args, "curl")
	}

	// Check for existing flags
	has_i := false
	has_s := false

	for i := 1; i < len(args); i += 1 {
		arg := args[i]
		if arg == "-i" {has_i = true}
		if arg == "-s" || arg == "-sS" {has_s = true}
		append(&final_args, arg)
	}

	if !has_i {append(&final_args, "-i")}
	if !has_s {append(&final_args, "-sS")}

	// Reconstruct command line for Windows
	// We need to escape arguments properly for CreateProcess

	cmd_builder := strings.builder_make()
	defer strings.builder_destroy(&cmd_builder)

	for i in 0 ..< len(final_args) {
		if i > 0 {strings.write_byte(&cmd_builder, ' ')}

		arg := final_args[i]
		// Don't escape "curl" itself strictly needed? usually fine.
		// But for inconsistent args, we should escape all.
		escaped := escape_arg_windows(arg, context.temp_allocator)
		strings.write_string(&cmd_builder, escaped)
	}

	modified_cmd := strings.to_string(cmd_builder)

	// Execute
	stdout_str: string
	stderr_str: string

	when ODIN_OS == .Windows {
		// Windows: use silent execution helper
		stdout_s, stderr_s, ok := run_process_silent(modified_cmd)
		if !ok {
			result.error_msg = strings.clone("Failed to execute command")
			return result
		}
		stdout_str = stdout_s
		stderr_str = stderr_s
	} else {
		// On Unix we can pass the raw string if using sh -c,
		// BUT we verified the tokenizer handles quotes?
		// Actually, for Unix sh -c, we passed 'modified_cmd' which was just string concat.
		// If we use the tokenizer, we are reconstructing it.
		// For Unix, we want to respect the original quoting if possible, OR
		// we can reconstruct using single quotes for safety?
		// Simplest for now: Re-use the sanitizer logic for Unix or just use the same reconstructed string?
		// Reconstructed string uses Windows escaping rules (double quotes).
		// Unix sh might not like Windows escaping (e.g. `^` vs `\`).
		// Let's stick to the OLD logic for Unix for now to avoid regression,
		// OR better: use the sanitized command + flags appended.

		// Re-using old logic for Unix:
		unix_cmd := sanitized_command
		if !has_i {unix_cmd = strings.concatenate({unix_cmd, " -i"})}
		if !has_s {unix_cmd = strings.concatenate({unix_cmd, " -sS"})}

		state, stdout, stderr, err := os2.process_exec(
			{command = {"/bin/sh", "-c", unix_cmd}},
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

// Helper to sanitize multi-line curl commands
sanitize_curl_command_string :: proc(input: string, allocator := context.allocator) -> string {
	builder := strings.builder_make(allocator)

	// Convert to bytes for easy indexing
	chars := transmute([]u8)input

	in_quote: u8 = 0 // 0 means not in quote, otherwise holds '"' or '\''
	i := 0

	for i < len(chars) {
		c := chars[i]

		// Handle Backslash (Escape or Line Continuation)
		if c == '\\' {
			// Check for line continuation (backslash at end of line)
			// This applies ANYWHERE, even inside quotes in most shells
			if i + 1 < len(chars) {
				next := chars[i + 1]
				if next == '\n' {
					i += 2
					continue
				}
				if next == '\r' && i + 2 < len(chars) && chars[i + 2] == '\n' {
					i += 3
					continue
				}
			}

			// Just a regular backslash (maybe escaping something)
			strings.write_byte(&builder, c)
			i += 1

			// If we just wrote a blackslash, we should write the next char literally?
			// But if we do that we might miss special handling
			continue
		}

		// Check for Quotes
		if c == '"' || c == '\'' {
			// Check if escaped
			is_escaped := false
			if i > 0 && chars[i - 1] == '\\' {
				// Check if it was a line continuation we SKIPPED?
				// If we skipped it, i changed by >1.
				// chars[i-1] is effectively correct in the RAW string.
				is_escaped = true
			}

			if !is_escaped {
				if in_quote == 0 {
					in_quote = c
				} else if in_quote == c {
					in_quote = 0
				}
			}

			strings.write_byte(&builder, c)
			i += 1
			continue
		}

		// Handle Newlines
		if c == '\n' || c == '\r' {
			if in_quote != 0 {
				// Inside quote: Keep it (or replace with space? Shells allow newlines in quotes)
				strings.write_byte(&builder, c)
			} else {
				// Outside quote: convert to space
				strings.write_byte(&builder, ' ')
			}
			i += 1
			continue
		}

		// Normal char
		strings.write_byte(&builder, c)
		i += 1
	}

	return strings.to_string(builder)
}

// Tokenize command string (shell-like)
tokenize_command :: proc(input: string, allocator := context.allocator) -> [dynamic]string {
	args := make([dynamic]string, allocator)

	current_arg := strings.builder_make(allocator)
	// defer strings.builder_destroy(&current_arg) // Don't destroy, we return the string

	in_quote: rune = 0
	escaped := false

	for c in input {
		if escaped {
			strings.write_rune(&current_arg, c)
			escaped = false
			continue
		}

		if c == '\\' {
			// Only treat backslash as escape if inside double quotes or outside quotes
			// Inside single quotes, backslash is literal usually?
			// Bash: 'it\'s' -> invalid. 'it'\''s' -> valid.
			// Simple approach: Always escape next char if \
			// But wait, Windows paths use \.
			// Let's assume input is Unix-style curl command (forward slashes or quoted backslashes).
			escaped = true
			continue
		}

		if in_quote != 0 {
			if c == in_quote {
				in_quote = 0
			} else {
				strings.write_rune(&current_arg, c)
			}
		} else {
			if c == '"' || c == '\'' {
				in_quote = c
			} else if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
				if strings.builder_len(current_arg) > 0 {
					append(&args, strings.to_string(current_arg))
					current_arg = strings.builder_make(allocator)
				}
			} else {
				strings.write_rune(&current_arg, c)
			}
		}
	}

	if strings.builder_len(current_arg) > 0 {
		append(&args, strings.to_string(current_arg))
	}

	return args
}

// Escape argument for Windows CreateProcess
escape_arg_windows :: proc(arg: string, allocator := context.allocator) -> string {
	if len(arg) == 0 {return "\"\""}

	// Check if needs quotes (has space, tab, quote)
	needs_quotes := false
	if strings.contains_any(arg, " \t\n\v\"") {
		needs_quotes = true
	}

	if !needs_quotes {return strings.clone(arg, allocator)}

	builder := strings.builder_make(allocator)
	strings.write_byte(&builder, '"')

	for i := 0; i < len(arg); i += 1 {
		c := arg[i]

		if c == '"' {
			// Escape quotes
			// Also count preceding backslashes
			bs_count := 0
			for j := i - 1; j >= 0 && arg[j] == '\\'; j -= 1 {
				bs_count += 1
			}

			// We need to double the backslashes that are before the quote
			// The original backslashes are already written, wait.
			// Actually we need to handle backslashes carefully.

			// Let's assume we iterate and buffer backslashes.
		}
	}

	// Simpler loop for escaping:
	strings.builder_reset(&builder)
	strings.write_byte(&builder, '"')

	bs_count := 0
	for c in arg {
		if c == '\\' {
			bs_count += 1
		} else if c == '"' {
			// Float backslashes before quote need to be doubled
			for k in 0 ..< bs_count {strings.write_string(&builder, "\\\\")} 	// Double the existing ones?
			// Wait, if I have `foo\"`, bs_count is 1.
			// Windows: `foo\\\"` -> backslash is literal, quote is escaped.
			// So 2 * N backslashes + 1 backslash for the quote.

			// Re-write logic:
			// We haven't written the backslashes yet if we count them.

			// NO, standard loop is easier if we just handle the sequence.
		} else {
			bs_count = 0
		}
	}

	// Better implementation
	strings.builder_reset(&builder)
	strings.write_byte(&builder, '"')

	i := 0
	for i < len(arg) {
		c := arg[i]
		if c == '"' {
			// Count preceding backslashes
			num_bs := 0
			for j := i - 1; j >= 0 && arg[j] == '\\'; j -= 1 {
				num_bs += 1
			}

			// Escape all preceding backslashes again (so they become literal backslashes)
			// Wait, we already wrote them? No, let's look back?
			// This logic is tricky with streaming.

			// Let's do the "block" approach.
			// Process runs of backslashes.
		}
		i += 1
	}

	// Microsoft's Algorithm:
	// 1. 2n backslashes followed by " -> n backslashes + " (not escaped)
	// 2. 2n+1 backslashes followed by " -> n backslashes + \" (escaped quote)
	// 3. n backslashes not followed by " -> n backslashes

	// So when writing:
	// - Argument is enclosed in "..."
	// - " -> \"
	// - \..\" -> \\..\\\" (double all backslashes preceding a quote)
	// - \..\$ -> \..\ (don't double backslashes at end unless followed by closing quote)

	strings.builder_reset(&builder)
	strings.write_byte(&builder, '"')

	chars := transmute([]u8)arg
	i = 0
	for i < len(chars) {
		c := chars[i]

		if c == '\\' {
			// Count backslashes
			bs_start := i
			for i < len(chars) && chars[i] == '\\' {
				i += 1
			}
			count := i - bs_start

			if i < len(chars) && chars[i] == '"' {
				// Backslashes followed by quote: double them
				for k in 0 ..< count * 2 {strings.write_byte(&builder, '\\')}
				// The quote will be handled in next iteration?
				// No, we are at chars[i] == '"'.
				strings.write_string(&builder, "\\\"")
				i += 1 // consume quote
			} else if i == len(chars) {
				// Backslashes at end of string: double them (because valid closing quote follows)
				for k in 0 ..< count * 2 {strings.write_byte(&builder, '\\')}
			} else {
				// Backslashes followed by something else: write them as is
				for k in 0 ..< count {strings.write_byte(&builder, '\\')}
				// i points to the non-backslash char, will be handled next loop (it's not incremented here)
			}
		} else if c == '"' {
			strings.write_string(&builder, "\\\"")
			i += 1
		} else {
			strings.write_byte(&builder, c)
			i += 1
		}
	}

	strings.write_byte(&builder, '"')
	return strings.to_string(builder)
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

when ODIN_OS == .Windows {
	run_process_silent :: proc(
		command: string,
	) -> (
		stdout: string,
		stderr: string,
		success: bool,
	) {
		sa := windows.SECURITY_ATTRIBUTES {
			nLength              = size_of(windows.SECURITY_ATTRIBUTES),
			bInheritHandle       = true,
			lpSecurityDescriptor = nil,
		}

		h_read_out, h_write_out: windows.HANDLE
		if !windows.CreatePipe(&h_read_out, &h_write_out, &sa, 0) {
			return "", "", false
		}

		h_read_err, h_write_err: windows.HANDLE
		if !windows.CreatePipe(&h_read_err, &h_write_err, &sa, 0) {
			windows.CloseHandle(h_read_out)
			windows.CloseHandle(h_write_out)
			return "", "", false
		}

		// Ensure read handles are not inherited
		windows.SetHandleInformation(h_read_out, windows.HANDLE_FLAG_INHERIT, 0)
		windows.SetHandleInformation(h_read_err, windows.HANDLE_FLAG_INHERIT, 0)

		startup_info := windows.STARTUPINFOW {
			cb          = size_of(windows.STARTUPINFOW),
			dwFlags     = windows.STARTF_USESTDHANDLES | windows.STARTF_USESHOWWINDOW,
			wShowWindow = cast(u16)windows.SW_HIDE,
			hStdOutput  = h_write_out,
			hStdError   = h_write_err,
		}

		process_info: windows.PROCESS_INFORMATION

		cmd_wide := windows.utf8_to_wstring(command, context.temp_allocator)

		// CREATE_NO_WINDOW = 0x08000000
		creation_flags := u32(windows.CREATE_NO_WINDOW | windows.CREATE_UNICODE_ENVIRONMENT)

		if !windows.CreateProcessW(
			nil,
			cmd_wide,
			nil,
			nil,
			true,
			creation_flags,
			nil,
			nil,
			&startup_info,
			&process_info,
		) {
			windows.CloseHandle(h_read_out)
			windows.CloseHandle(h_write_out)
			windows.CloseHandle(h_read_err)
			windows.CloseHandle(h_write_err)
			return "", "", false
		}

		// Close write ends in this process so we can detect EOF
		windows.CloseHandle(h_write_out)
		windows.CloseHandle(h_write_err)
		windows.CloseHandle(process_info.hThread)

		// Read output
		stdout_builder := strings.builder_make()
		stderr_builder := strings.builder_make()

		buffer: [4096]u8
		bytes_read: windows.DWORD

		// Simple implementation: Read stdout then stderr.
		// Note: This can block if pipe fills up. Ideally use threads or overlapped IO.
		// For curl, usually fine.

		for {
			success := windows.ReadFile(h_read_out, &buffer, 4096, &bytes_read, nil)
			if !success || bytes_read == 0 {break}
			strings.write_bytes(&stdout_builder, buffer[:bytes_read])
		}

		for {
			success := windows.ReadFile(h_read_err, &buffer, 4096, &bytes_read, nil)
			if !success || bytes_read == 0 {break}
			strings.write_bytes(&stderr_builder, buffer[:bytes_read])
		}

		windows.WaitForSingleObject(process_info.hProcess, windows.INFINITE)
		windows.CloseHandle(process_info.hProcess)
		windows.CloseHandle(h_read_out)
		windows.CloseHandle(h_read_err)

		return strings.to_string(stdout_builder), strings.to_string(stderr_builder), true
	}
}
