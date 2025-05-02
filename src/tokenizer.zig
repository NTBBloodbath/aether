const std = @import("std");

pub const TokenType = enum {
    Identifier,
    Number,
    Boolean,
    String,
    Char,
    Plus,
    Minus,
    Slash,
    Star,
    Modulus,
    Pipe,
    Colon,
    Semicolon,
    Comma,
    Newline,
    KeywordLet,
    KeywordFn,
    KeywordReturn,
    KeywordIf,
    KeywordElse,
    KeywordTrue,
    KeywordFalse,
    KeywordNil,
    TypeInt,
    TypeFloat,
    TypeBool,
    TypeChar,
    TypeString,
    Eq,
    EqEq,
    NotEq,
    Less,
    LessEq,
    Greater,
    GreaterEq,
    Arrow,
    LParen,
    RParen,
    LBrace,
    RBrace,
    Eof,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    start: usize, // Start index in source
    end: usize, // End index in source
    line: u32,
    column: u32,
};

pub const Tokenizer = struct {
    source: []const u8,
    position: usize = 0,
    line: u32 = 1,
    column: u32 = 1,

    pub fn next(self: *Tokenizer) !Token {
        while (self.position < self.source.len) {
            const start_pos = self.position;

            const char = self.source[self.position];
            switch (char) {
                ' ', '\t' => {
                    self.column += 1;
                    self.position += 1; // Skip whitespace
                    continue;
                },
                // Skip newlines ONLY if they are not part of an expression
                '\n' => {
                    self.line += 1;
                    self.column = 1;
                    self.position += 1;
                    if (self.isMidExpression()) {
                        // Treat newline as whitespace
                        continue;
                    } else {
                        // Only return newline as statement separator if previous token wasn't newline
                        if (self.position == 0 or self.source[self.position - 1] != '\n')
                            return Token{ .type = .Newline, .value = "\n", .start = start_pos, .end = self.position, .line = self.line, .column = self.column };
                    }
                },
                '+' => return self.singleToken(.Plus),
                '-' => {
                    // Check for arrow
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '>') {
                        self.column += 2;
                        self.position += 2;
                        return Token{ .type = .Arrow, .value = "->", .start = start_pos, .end = self.position, .line = self.line, .column = self.column };
                    }
                    return self.singleToken(.Minus);
                },
                '*' => return self.singleToken(.Star),
                '/' => return self.singleToken(.Slash),
                '%' => return self.singleToken(.Modulus),
                ':' => return self.singleToken(.Colon),
                ';' => {
                    // Skip all characters until end of line then skip to next token after comment
                    while (self.position < self.source.len and self.source[self.position] != '\n')
                        self.position += 1;
                    continue;
                },
                ',' => return self.singleToken(.Comma),
                '|' => {
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '>') {
                        self.column += 2;
                        self.position += 2;
                        return Token{ .type = .Pipe, .value = "|>", .start = start_pos, .end = self.position, .line = self.line, .column = self.column };
                    }
                    return error.InvalidCharacter;
                },
                '=' => {
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '=') {
                        self.column += 2;
                        self.position += 2;
                        return Token{ .type = .EqEq, .value = "==", .start = start_pos, .end = self.position, .line = self.line, .column = self.column };
                    }
                    return self.singleToken(.Eq);
                },
                '<' => {
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '=') {
                        self.column += 2;
                        self.position += 2;
                        return Token{ .type = .LessEq, .value = "<=", .start = start_pos, .end = self.position, .line = self.line, .column = self.column };
                    }
                    return self.singleToken(.Less);
                },
                '>' => {
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '=') {
                        self.column += 2;
                        self.position += 2;
                        return Token{ .type = .GreaterEq, .value = ">=", .start = start_pos, .end = self.position, .line = self.line, .column = self.column };
                    }
                    return self.singleToken(.Greater);
                },
                '!' => {
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '=') {
                        self.column += 2;
                        self.position += 2;
                        return Token{ .type = .NotEq, .value = "!=", .start = start_pos, .end = self.position, .line = self.line, .column = self.column };
                    }
                    // TODO: handle this case as a boolean condition checker
                    // return self.singleToken(.Not);
                    return error.InvalidCharacter;
                },
                '(' => return self.singleToken(.LParen),
                ')' => return self.singleToken(.RParen),
                '{' => return self.singleToken(.LBrace),
                '}' => return self.singleToken(.RBrace),
                '"' => return try self.parseString(),
                '\'' => return try self.parseChar(),
                '0'...'9' => return self.parseNumber(),
                'a'...'z', 'A'...'Z' => {
                    const ident = self.parseIdentifier();
                    return if (std.mem.eql(u8, ident.value, "if"))
                        Token{ .type = .KeywordIf, .value = "if", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "else"))
                        Token{ .type = .KeywordElse, .value = "else", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "let"))
                        Token{ .type = .KeywordLet, .value = "let", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "fn"))
                        Token{ .type = .KeywordFn, .value = "fn", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "return"))
                        Token{ .type = .KeywordReturn, .value = "return", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "true"))
                        Token{ .type = .KeywordTrue, .value = "true", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "false"))
                        Token{ .type = .KeywordFalse, .value = "false", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "nil"))
                        Token{ .type = .KeywordNil, .value = "nil", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "int"))
                        Token{ .type = .TypeInt, .value = "int", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "float"))
                        Token{ .type = .TypeFloat, .value = "float", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "bool"))
                        Token{ .type = .TypeBool, .value = "bool", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "char"))
                        Token{ .type = .TypeChar, .value = "char", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else if (std.mem.eql(u8, ident.value, "string"))
                        Token{ .type = .TypeString, .value = "string", .start = start_pos, .end = self.position, .line = self.line, .column = self.column }
                    else
                        ident;
                },
                else => {
                    std.debug.print("Error at line {d}:{d} - Invalid character '{c}'\n", .{ self.line, self.column, char });
                    return error.InvalidCharacter;
                },
            }
        }

        return Token{ .type = .Eof, .value = "", .start = self.position, .end = self.position, .line = self.line, .column = self.column };
    }

    fn singleToken(self: *Tokenizer, t_type: TokenType) Token {
        const value = self.source[self.position .. self.position + 1];
        self.column += 1;
        self.position += 1;

        return .{ .type = t_type, .value = value, .start = self.position - 1, .end = self.position, .line = self.line, .column = self.column };
    }

    // Parse multi-digit numbers
    fn parseNumber(self: *Tokenizer) Token {
        const start = self.position;
        while (self.position < self.source.len) : (self.position += 1) {
            const c = self.source[self.position];
            if (!std.ascii.isDigit(c) and c != '.') break;
            self.column += 1;
        }

        return .{
            .type = .Number,
            .value = self.source[start..self.position],
            .start = start,
            .end = self.position,
            .line = self.line,
            .column = self.column,
        };
    }

    fn parseChar(self: *Tokenizer) !Token {
        self.column += 1;
        self.position += 1; // Skip opening '
        const start = self.position;

        if (self.position >= self.source.len) return error.UnterminatedChar;

        if (self.source[self.position] == '\\') {
            self.column += 1;
            self.position += 1;
            if (self.position >= self.source.len) return error.UnterminatedChar;
        }

        const char_len = std.unicode.utf8ByteSequenceLength(self.source[self.position]) catch 1;
        self.position += char_len;

        if (self.position >= self.source.len or self.source[self.position] != '\'') {
            return error.InvalidCharLiteral;
        }

        const value = self.source[start..self.position];
        self.column += 1;
        self.position += 1;

        return Token{ .type = .Char, .value = value, .start = start, .end = self.position, .line = self.line, .column = self.column };
    }

    fn parseString(self: *Tokenizer) !Token {
        self.column += 1;
        self.position += 1; // Skip opening "
        const start = self.position;
        var escape = false;

        while (self.position < self.source.len) : (self.position += 1) {
            const c = self.source[self.position];

            if (escape) {
                escape = false;
                self.column += 1;
                self.position += 1;
                continue;
            }

            if (c == '\\') {
                escape = true;
                self.column += 1;
                self.position += 1;
                continue;
            }

            if (c == '"') {
                const value = self.source[start..self.position];
                self.column += 1;
                self.position += 1; // Skip closing "
                return Token{ .type = .String, .value = value, .start = start, .end = self.position, .line = self.line, .column = self.column };
            }

            self.column += 1;
        }

        return error.UnterminatedString;
    }

    fn parseIdentifier(self: *Tokenizer) Token {
        const start = self.position;
        while (self.position < self.source.len) : (self.position += 1) {
            const c = self.source[self.position];
            if (!std.ascii.isAlphanumeric(c) and c != '_') break;
            self.column += 1;
        }

        return .{
            .type = .Identifier,
            .value = self.source[start..self.position],
            .start = start,
            .end = self.position,
            .line = self.line,
            .column = self.column,
        };
    }

    fn isMidExpression(self: *Tokenizer) bool {
        if (self.position == 0) return false;
        const prev_char = self.source[self.position - 1];
        return switch (prev_char) {
            '+', '-', '*', '/', '%', '(', ')', ':' => true,
            else => false,
        };
    }
};
