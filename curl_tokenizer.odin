package main

import "core:strings"

// Token types for curl command syntax highlighting
TokenType :: enum {
	Command, // "curl"
	Flag, // -X, -H, -d, --data-raw, etc.
	Method, // GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
	URL, // https://... or http://...
	HeaderName, // "Content-Type:" part of header
	HeaderValue, // value part of header
	String, // quoted strings (both " and ')
	JsonBrace, // { } [ ]
	Data, // unquoted data
	Whitespace, // spaces between tokens
	Error, // unclosed quotes, invalid syntax
}

Token :: struct {
	type:      TokenType,
	start:     int, // start position in source string (inclusive)
	end:       int, // end position in source string (exclusive)
	has_error: bool, // for error highlighting (e.g., unclosed quote)
}

// Check if string starts with a known HTTP method
is_http_method :: proc(s: string) -> bool {
	methods := []string{"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"}
	for m in methods {
		if s == m {return true}
	}
	return false
}

// Check if character is a flag start
is_flag_start :: proc(input: string, pos: int) -> bool {
	if pos >= len(input) {return false}
	if input[pos] != '-' {return false}
	// Must be at start or after whitespace
	if pos > 0 && input[pos - 1] != ' ' && input[pos - 1] != '\t' {return false}
	return true
}

// Check if string looks like a URL
is_url :: proc(s: string) -> bool {
	return strings.has_prefix(s, "http://") || strings.has_prefix(s, "https://")
}

// Tokenize a curl command into tokens for syntax highlighting
// Returns both the tokens and the processed string (with backslashes removed)
tokenize_curl :: proc(
	input: string,
	allocator := context.allocator,
) -> (
	tokens: [dynamic]Token,
	processed_str: string,
) {
	tokens = make([dynamic]Token, allocator)

	if len(input) == 0 {
		return tokens, ""
	}

	// Preprocess: Remove backslash line continuations
	// This creates a clean string where flags are properly recognized
	clean_input := strings.builder_make(allocator)
	for i := 0; i < len(input); i += 1 {
		ch := input[i]
		if ch == '\\' {
			// Skip backslash and any following newlines (line continuation)
			for i + 1 < len(input) && (input[i + 1] == '\n' || input[i + 1] == '\r') {
				i += 1
			}
			// Add a space to separate tokens if needed
			if strings.builder_len(clean_input) > 0 {
				last_char := strings.to_string(clean_input)[strings.builder_len(clean_input) - 1]
				if last_char != ' ' && last_char != '\t' {
					strings.write_byte(&clean_input, ' ')
				}
			}
		} else {
			strings.write_byte(&clean_input, ch)
		}
	}

	processed := strings.to_string(clean_input)

	pos := 0
	last_flag := "" // Track the last flag for context (e.g., -H means next is header)
	expect_flag_value := false

	for pos < len(processed) {

		// Skip and tokenize whitespace
		if processed[pos] == ' ' || processed[pos] == '\t' {
			start := pos
			for pos < len(processed) && (processed[pos] == ' ' || processed[pos] == '\t') {
				pos += 1
			}
			append(&tokens, Token{type = .Whitespace, start = start, end = pos})
			continue
		}

		// Handle quoted strings
		if processed[pos] == '"' || processed[pos] == '\'' {
			quote_char := processed[pos]
			start := pos
			pos += 1
			has_error := true

			for pos < len(processed) {
				if processed[pos] == '\\' && pos + 1 < len(processed) {
					// Skip escaped character
					pos += 2
				} else if processed[pos] == quote_char {
					pos += 1
					has_error = false
					break
				} else {
					pos += 1
				}
			}

			// Determine token type based on context
			token_type := TokenType.String
			if last_flag == "-H" || last_flag == "--header" {
				// This is a header value, but we'll still mark as String for now
				// Could be enhanced to split into HeaderName:HeaderValue later
				token_type = .String
			}

			append(
				&tokens,
				Token{type = token_type, start = start, end = pos, has_error = has_error},
			)
			expect_flag_value = false
			continue
		}

		// Handle flags (start with -)
		if is_flag_start(processed, pos) {
			start := pos
			pos += 1

			// Handle -- long flags
			if pos < len(processed) && processed[pos] == '-' {
				pos += 1
			}

			// Read flag name
			for pos < len(processed) &&
			    processed[pos] != ' ' &&
			    processed[pos] != '\t' &&
			    processed[pos] != '=' {
				pos += 1
			}

			flag_str := processed[start:pos]
			last_flag = flag_str
			expect_flag_value = true

			append(&tokens, Token{type = .Flag, start = start, end = pos})
			continue
		}

		// Handle JSON braces
		if processed[pos] == '{' ||
		   processed[pos] == '}' ||
		   processed[pos] == '[' ||
		   processed[pos] == ']' {
			append(&tokens, Token{type = .JsonBrace, start = pos, end = pos + 1})
			pos += 1
			continue
		}

		// Read a word (until whitespace)
		start := pos
		for pos < len(processed) && processed[pos] != ' ' && processed[pos] != '\t' {
			pos += 1
		}

		word := processed[start:pos]

		// Determine token type
		token_type := TokenType.Data

		if word == "curl" && start == 0 {
			token_type = .Command
		} else if is_http_method(word) {
			token_type = .Method
		} else if is_url(word) {
			token_type = .URL
		}

		append(&tokens, Token{type = token_type, start = start, end = pos})
		expect_flag_value = false
	}

	return tokens, processed
}

// Format curl command into multiple display lines
// Each line is a slice of tokens
DisplayLine :: struct {
	tokens: [dynamic]Token,
	indent: int, // number of spaces to indent
}

// Flags that should start a new line
should_break_before :: proc(input: string, token: Token) -> bool {
	if token.type != .Flag {return false}

	flag_str := input[token.start:token.end]
	break_flags := []string {
		"-X",
		"-H",
		"-d",
		"--header",
		"--data",
		"--data-raw",
		"--data-binary",
		"--data-urlencode",
		"-F",
		"--form",
		"-u",
		"--user",
		"-A",
		"--user-agent",
		"-e",
		"--referer",
		"-b",
		"--cookie",
		"-c",
		"--cookie-jar",
		"-o",
		"--output",
		"-O",
		"--remote-name",
		"-L",
		"--location",
		"-k",
		"--insecure",
		"-v",
		"--verbose",
		"-s",
		"--silent",
	}

	for bf in break_flags {
		if flag_str == bf {return true}
	}
	return false
}

// Split tokens into display lines with proper breaks
format_display_lines :: proc(
	input: string,
	tokens: []Token,
	allocator := context.allocator,
) -> [dynamic]DisplayLine {
	lines := make([dynamic]DisplayLine, allocator)

	if len(tokens) == 0 {
		return lines
	}

	// First line (no indent)
	current_line := DisplayLine {
		tokens = make([dynamic]Token, allocator),
		indent = 0,
	}

	INDENT_SIZE :: 5 // Spaces for continuation lines
	is_first_line := true

	for i := 0; i < len(tokens); i += 1 {
		token := tokens[i]

		// Check if we should start a new line before this token
		if !is_first_line && should_break_before(input, token) {
			// Strip trailing whitespace from current line
			for len(current_line.tokens) > 0 &&
			    current_line.tokens[len(current_line.tokens) - 1].type == .Whitespace {
				pop(&current_line.tokens)
			}

			// Start new line if current has content
			if len(current_line.tokens) > 0 {
				append(&lines, current_line)
				current_line = DisplayLine {
					tokens = make([dynamic]Token, allocator),
					indent = INDENT_SIZE,
				}
			}
		}

		// Skip whitespace at the start of a line
		if token.type == .Whitespace && len(current_line.tokens) == 0 {
			continue
		}

		append(&current_line.tokens, token)
		is_first_line = false
	}

	// Don't forget the last line
	if len(current_line.tokens) > 0 {
		append(&lines, current_line)
	}

	return lines
}

// Check if there are any error tokens
has_syntax_errors :: proc(tokens: []Token) -> bool {
	for t in tokens {
		if t.has_error {return true}
	}
	return false
}

// Get the token at a specific buffer position (for cursor highlighting)
get_token_at_position :: proc(tokens: []Token, pos: int) -> Maybe(Token) {
	for t in tokens {
		if pos >= t.start && pos < t.end {
			return t
		}
	}
	return nil
}

// Map buffer position to display (line, column)
// Returns (line_index, column_position) for rendering cursor
buffer_pos_to_display :: proc(
	lines: []DisplayLine,
	tokens: []Token,
	buffer_pos: int,
	input: string,
) -> (
	line_idx: int,
	col: int,
) {
	if len(lines) == 0 {
		return 0, 0
	}

	// Find which token contains this position
	current_pos := 0

	for line_i := 0; line_i < len(lines); line_i += 1 {
		line := lines[line_i]
		line_start_col := line.indent

		for t in line.tokens {
			token_len := t.end - t.start

			// Check if buffer_pos falls within this token
			if buffer_pos >= t.start && buffer_pos <= t.end {
				// Calculate column within the token
				offset_in_token := buffer_pos - t.start
				return line_i, line_start_col + offset_in_token
			}

			line_start_col += token_len
		}
	}

	// If not found, return end of last line
	if len(lines) > 0 {
		last_line := lines[len(lines) - 1]
		col := last_line.indent
		for t in last_line.tokens {
			col += t.end - t.start
		}
		return len(lines) - 1, col
	}

	return 0, 0
}

// Free display lines
free_display_lines :: proc(lines: ^[dynamic]DisplayLine) {
	for &line in lines {
		delete(line.tokens)
	}
	delete(lines^)
}
