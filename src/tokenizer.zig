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
};

pub const Tokenizer = struct {
    source: []const u8,
    position: usize = 0,

    pub fn next(self: *Tokenizer) !Token {
        while (self.position < self.source.len) {
            const char = self.source[self.position];
            switch (char) {
                ' ', '\t' => {
                    self.position += 1; // Skip whitespace
                    continue;
                },
                // Skip newlines ONLY if they are not part of an expression
                '\n' => {
                    self.position += 1;
                    if (self.isMidExpression()) {
                        // Treat newline as whitespace
                        continue;
                    } else {
                        // Only return newline as statement separator if previous token wasn't newline
                        if (self.position == 0 or self.source[self.position - 1] != '\n')
                            return Token{ .type = .Newline, .value = "\n" };
                    }
                },
                '+' => return self.singleToken(.Plus),
                '-' => {
                    // Check for arrow
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '>') {
                        self.position += 2;
                        return Token{ .type = .Arrow, .value = "->" };
                    }
                    return self.singleToken(.Minus);
                },
                '*' => return self.singleToken(.Star),
                '/' => return self.singleToken(.Slash),
                '%' => return self.singleToken(.Modulus),
                ':' => return self.singleToken(.Colon),
                ',' => return self.singleToken(.Comma),
                '|' => {
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '>') {
                        self.position += 2;
                        return Token{ .type = .Pipe, .value = "|>" };
                    }
                    return error.InvalidCharacter;
                },
                '=' => {
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '=') {
                        self.position += 2;
                        return Token{ .type = .EqEq, .value = "==" };
                    }
                    return self.singleToken(.Eq);
                },
                '<' => {
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '=') {
                        self.position += 2;
                        return Token{ .type = .LessEq, .value = "<=" };
                    }
                    return self.singleToken(.Less);
                },
                '>' => {
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '=') {
                        self.position += 2;
                        return Token{ .type = .GreaterEq, .value = ">=" };
                    }
                    return self.singleToken(.Greater);
                },
                '!' => {
                    if (self.position + 1 < self.source.len and self.source[self.position + 1] == '=') {
                        self.position += 2;
                        return Token{ .type = .NotEq, .value = "!=" };
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
                        Token{ .type = .KeywordIf, .value = "if" }
                    else if (std.mem.eql(u8, ident.value, "else"))
                        Token{ .type = .KeywordElse, .value = "else" }
                    else if (std.mem.eql(u8, ident.value, "let"))
                        Token{ .type = .KeywordLet, .value = "let" }
                    else if (std.mem.eql(u8, ident.value, "fn"))
                        Token{ .type = .KeywordFn, .value = "fn" }
                    else if (std.mem.eql(u8, ident.value, "return"))
                        Token{ .type = .KeywordReturn, .value = "return" }
                    else if (std.mem.eql(u8, ident.value, "true"))
                        Token{ .type = .KeywordTrue, .value = "true" }
                    else if (std.mem.eql(u8, ident.value, "false"))
                        Token{ .type = .KeywordFalse, .value = "false" }
                    else if (std.mem.eql(u8, ident.value, "nil"))
                        Token{ .type = .KeywordNil, .value = "nil" }
                    else if (std.mem.eql(u8, ident.value, "int"))
                        Token{ .type = .TypeInt, .value = "int" }
                    else if (std.mem.eql(u8, ident.value, "float"))
                        Token{ .type = .TypeFloat, .value = "float" }
                    else if (std.mem.eql(u8, ident.value, "bool"))
                        Token{ .type = .TypeBool, .value = "bool" }
                    else if (std.mem.eql(u8, ident.value, "char"))
                        Token{ .type = .TypeChar, .value = "char" }
                    else if (std.mem.eql(u8, ident.value, "string"))
                        Token{ .type = .TypeString, .value = "string" }
                    else
                        ident;
                },
                else => {
                    std.debug.print("Invalid character '{c}'\n", .{char});
                    return error.InvalidCharacter;
                },
            }
        }

        return Token{ .type = .Eof, .value = "" };
    }

    fn singleToken(self: *Tokenizer, t_type: TokenType) Token {
        const value = self.source[self.position .. self.position + 1];
        self.position += 1;

        return .{ .type = t_type, .value = value };
    }

    // Parse multi-digit numbers
    fn parseNumber(self: *Tokenizer) Token {
        const start = self.position;
        while (self.position < self.source.len) : (self.position += 1) {
            const c = self.source[self.position];
            if (!std.ascii.isDigit(c) and c != '.') break;
        }

        return .{
            .type = .Number,
            .value = self.source[start..self.position],
        };
    }

    fn parseChar(self: *Tokenizer) !Token {
        self.position += 1; // Skip opening '
        const start = self.position;

        if (self.position >= self.source.len) return error.UnterminatedChar;

        if (self.source[self.position] == '\\') {
            self.position += 1;
            if (self.position >= self.source.len) return error.UnterminatedChar;
        }

        const char_len = std.unicode.utf8ByteSequenceLength(self.source[self.position]) catch 1;
        self.position += char_len;

        if (self.position >= self.source.len or self.source[self.position] != '\'') {
            return error.InvalidCharLiteral;
        }

        const value = self.source[start..self.position];
        self.position += 1;

        return Token{ .type = .Char, .value = value };
    }

    fn parseString(self: *Tokenizer) !Token {
        self.position += 1; // Skip opening "
        const start = self.position;
        var escape = false;

        while (self.position < self.source.len) : (self.position += 1) {
            const c = self.source[self.position];

            if (escape) {
                escape = false;
                self.position += 1;
                continue;
            }

            if (c == '\\') {
                escape = true;
                self.position += 1;
                continue;
            }

            if (c == '"') {
                const value = self.source[start..self.position];
                self.position += 1; // Skip closing "
                return Token{ .type = .String, .value = value };
            }
        }

        return error.UnterminatedString;
    }

    fn parseIdentifier(self: *Tokenizer) Token {
        const start = self.position;
        while (self.position < self.source.len) : (self.position += 1) {
            const c = self.source[self.position];
            if (!std.ascii.isAlphanumeric(c) and c != '_') break;
        }

        return .{
            .type = .Identifier,
            .value = self.source[start..self.position],
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
