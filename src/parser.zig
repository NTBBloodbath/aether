// TODO: improve error handling even more, implement error recovery

const std = @import("std");

const ast = @import("ast.zig");

const Token = @import("tokenizer.zig").Token;
const TokenType = @import("tokenizer.zig").TokenType;
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub const ParserError = error{
    UnexpectedToken,
    SyntaxError,
    InvalidCharacter, // Propagate tokenizer errors
    InvalidCharLiteral, // Propagate tokenizer errors
    InvalidCharEscape,
    InvalidType,
    UnterminatedString, // Propagate tokenizer errors
    UnterminatedChar, // Propagate tokenizer errors
    ExpectedIdentifier,
    PipeRightNotCallable,
    OutOfMemory,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokenizer: *Tokenizer,
    current_token: Token,

    pub fn init(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ParserError!Parser {
        const first_token = tokenizer.next() catch |err| switch (err) {
            error.UnterminatedString => return error.UnterminatedString,
            error.UnterminatedChar => return error.UnterminatedChar,
            error.InvalidCharLiteral => return error.InvalidCharLiteral,
            error.InvalidCharacter => return error.InvalidCharacter,
        };

        return Parser{
            .allocator = allocator,
            .tokenizer = tokenizer,
            .current_token = first_token,
        };
    }

    pub fn parseProgram(self: *Parser) !*ast.Program {
        const program = try ast.Program.create(self.allocator);

        while (self.current_token.type != .Eof) {
            // Skip leading newlines between statements
            while (self.current_token.type == .Newline) try self.advance();

            // Parse statement
            const stmt = try self.parseStatement();
            try program.statements.append(stmt);
        }

        return program;
    }

    pub fn parseStatement(self: *Parser) ParserError!*ast.Statement {
        return switch (self.current_token.type) {
            .KeywordLet => blk: {
                const decl = try self.parseVariableDecl();
                const stmt = try self.allocator.create(ast.Statement);
                stmt.* = .{ .VariableDecl = decl };
                break :blk stmt;
            },
            .KeywordReturn => blk: {
                const expr = try self.parseExpression();
                const ret = try self.allocator.create(ast.ReturnStmt);
                ret.* = .{ .value = expr };

                const stmt = try self.allocator.create(ast.Statement);
                stmt.* = .{ .Return = ret };
                break :blk stmt;
            },
            .KeywordFn => blk: {
                const func_decl = try self.parseFunctionDecl();
                const stmt = try self.allocator.create(ast.Statement);
                stmt.* = .{ .FunctionDecl = func_decl };
                break :blk stmt;
            },
            else => blk: {
                const expr = try self.parseExpression();
                const stmt = try self.allocator.create(ast.Statement);
                stmt.* = .{ .Expr = expr };
                break :blk stmt;
            },
        };
    }

    pub fn parseExpression(self: *Parser) ParserError!*ast.Expression {
        return try self.parsePrecedence(0);
    }

    fn parsePrecedence(self: *Parser, min_precedence: u8) !*ast.Expression {
        var left = try self.parsePrimary();

        while (true) {
            const op_token = self.current_token;
            const op_prec = self.getPrecedence();

            // Stop if not an operator or precedence too low
            if (op_prec == 0 or op_prec < min_precedence) break;

            try self.advance();

            // Handle pipe operator
            if (op_token.type == .Pipe) {
                const right = try self.parsePrecedence(op_prec + 1);

                // Transform pipe into function call
                switch (right.*) {
                    .FunctionCall => |func_call| {
                        // Prepend left to arguments
                        var new_args = std.ArrayList(*ast.Expression).init(self.allocator);
                        try new_args.append(left);
                        for (func_call.args.items) |arg| {
                            try new_args.append(arg);
                        }
                        left = try ast.FunctionCall.create(self.allocator, func_call.callee, new_args);
                    },
                    .VariableRef => |_| {
                        // Create new function call with left as first argument
                        var args = std.ArrayList(*ast.Expression).init(self.allocator);
                        try args.append(left);
                        left = try ast.FunctionCall.create(self.allocator, right, args);
                    },
                    // zig fmt: off
                    else => return self.failWithContext(
                        error.PipeRightNotCallable,
                        "Right side of |> must be a function call, got '{s}'",
                        .{@tagName(right.*)}
                    ),
                }
            } else {
                const right = try self.parsePrecedence(op_prec + 1);
                left = try ast.BinaryOp.create(self.allocator, left, op_token, right);
            }
        }

        return left;
    }

    fn parseLambda(self: *Parser) !*ast.Expression {
        // fn(param: type) -> return_type { ... }
        try self.expect(.KeywordFn);
        try self.expect(.LParen);

        var params = std.ArrayList(ast.Param).init(self.allocator);
        while (self.current_token.type != .RParen) {
            const name = try self.parseIdentifier();

            var type_name: ?[]const u8 = null;
            if (self.current_token.type == .Colon) {
                try self.advance();
                try self.validateType(self.current_token.type);
                type_name = self.current_token.value;
                try self.advance();
            }
            try self.advance();

            try params.append(.{ .name = name.value, .type_name = type_name });

            if (self.current_token.type != .Comma) break;
            try self.advance();
        }
        try self.expect(.RParen);

        // Parse return type
        try self.expect(.Arrow);
        const return_type = self.current_token.type;
        const return_type_name = self.current_token.value;
        try self.validateType(return_type);
        try self.advance();

        // Parse body
        try self.expect(.LBrace);
        const body = try self.parseExpression();
        try self.expect(.RBrace);

        return ast.Lambda.create(self.allocator, params, return_type_name, body);
    }

    fn parseFunctionDecl(self: *Parser) !*ast.FunctionDecl {
        try self.expect(.KeywordFn);
        const name = try self.parseIdentifier();

        // Parameters
        try self.expect(.LParen);
        var params = std.ArrayList(ast.Param).init(self.allocator);
        while (self.current_token.type != .RParen) {
            const param_name = try self.parseIdentifier();

            var param_type: ?[]const u8 = null;
            if (self.current_token.type == .Colon) {
                try self.advance();
                try self.validateType(self.current_token.type);
                param_type = self.current_token.value;
                try self.advance();
            }

            try params.append(.{ .name = param_name.value, .type_name = param_type });

            if (self.current_token.type == .Comma) try self.advance() else break;
        }
        try self.expect(.RParen);

        // Return type
        try self.expect(.Arrow);
        const return_type = self.current_token.value;
        try self.validateType(self.current_token.type);
        try self.advance();

        // Body
        try self.expect(.LBrace);
        const body = try self.parseExpression();
        try self.expect(.RBrace);

        const func_decl = try ast.FunctionDecl.create(self.allocator, name.value, params, return_type, body);
        return func_decl.FunctionDecl;
    }

    fn parseFunctionCall(self: *Parser, callee: *ast.Expression) !*ast.Expression {
        // TODO: validate argument types and arity
        try self.advance(); // Skip '('

        var args = std.ArrayList(*ast.Expression).init(self.allocator);
        while (self.current_token.type != .RParen) {
            const arg = try self.parseExpression();
            try args.append(arg);

            if (self.current_token.type != .Comma) break;
            try self.advance();
        }
        try self.expect(.RParen);

        return ast.FunctionCall.create(self.allocator, callee, args);
    }

    fn parsePrimary(self: *Parser) !*ast.Expression {
        return switch (self.current_token.type) {
            .Number => blk: {
                const num_token = self.current_token;
                try self.advance();
                break :blk try ast.NumberLiteral.create(num_token.value, self.allocator);
            },
            .Char => blk: {
                const value = try parseCharValue(self.current_token.value);
                try self.advance();
                break :blk try ast.CharLiteral.create(self.allocator, value);
            },
            .String => blk: {
                const value = self.current_token.value;
                try self.advance();
                break :blk try ast.StringLiteral.create(self.allocator, value);
            },
            .LParen => blk: {
                try self.advance();
                const expr = try self.parseExpression();
                try self.expect(.RParen);
                break :blk expr;
            },
            .Identifier => blk: {
                const ident = try ast.VariableRef.create(self.allocator, self.current_token.value);
                try self.advance();

                // Check if this is a function call
                if (self.current_token.type == .LParen) {
                    break :blk try self.parseFunctionCall(ident);
                }

                break :blk ident;
            },
            .KeywordFn => try self.parseLambda(),
            .KeywordReturn => try self.parseReturn(),
            .KeywordIf => try self.parseIfExpr(),
            .KeywordTrue => {
                try self.advance();
                return ast.BooleanLiteral.create(self.allocator, true);
            },
            .KeywordFalse => {
                try self.advance();
                return ast.BooleanLiteral.create(self.allocator, false);
            },
            .KeywordNil => {
                try self.advance();
                return ast.NilLiteral.create(self.allocator);
            },
            // zig fmt: off
            else => return self.failWithContext(
                error.UnexpectedToken,
                "Unexpected token in expression: '{s}'",
                .{@tagName(self.current_token.type)}
            ),
        };
    }

    fn parseCharValue(str: []const u8) !u21 {
        // Handle escaped characters
        if (str[0] == '\\') {
            return switch (str[1]) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '0' => 0,
                '\\' => '\\',
                '\'' => '\'',
                '"' => '"',
                else => return error.InvalidCharEscape,
            };
        }
        return std.unicode.utf8Decode(str) catch {
            std.debug.print("Invalid char literal: {s}\n", .{str});
            return 0xFFFD; // Unicode replacement character
        };
    }

    fn parseVariableDecl(self: *Parser) !*ast.VariableDecl {
        // Ensure we are starting with 'let'
        try self.expect(.KeywordLet);
        const name = try self.parseIdentifier();

        // Optional type annotation
        var type_name: ?[]const u8 = null;
        if (self.current_token.type == .Colon) {
            try self.advance();
            const token_type = self.current_token.type;
            type_name = self.current_token.value;
            // Check if the type is valid
            try self.validateType(token_type);
            try self.advance();
        }

        try self.expect(.Eq);
        const value = try self.parseExpression();
        const variable = try ast.VariableDecl.create(self.allocator, name.value, type_name, value);
        return variable.VariableDecl;
    }

    fn parseIfExpr(self: *Parser) !*ast.Expression {
        // Ensure we are starting with 'if'
        try self.expect(.KeywordIf);
        const condition = try self.parseExpression();
        try self.expect(.LBrace);
        const then_branch = try self.parseExpression();
        try self.expect(.RBrace);

        var else_branch: ?*ast.Expression = null;
        if (self.current_token.type == .KeywordElse) {
            try self.advance();
            try self.expect(.LBrace);
            else_branch = try self.parseExpression();
            try self.expect(.RBrace);
        }

        return ast.IfExpr.create(self.allocator, condition, then_branch, else_branch);
    }

    // Parses return in expressions (e.g. function body)
    fn parseReturn(self: *Parser) !*ast.Expression {
        // Ensure we are starting with 'return'
        try self.expect(.KeywordReturn);

        const expr = try self.parseExpression();
        return try ast.ReturnStmt.create(self.allocator, expr);
    }

    fn parseIdentifier(self: *Parser) !Token {
        if (self.current_token.type != .Identifier) {
            // zig fmt: off
            return self.failWithContext(
                error.ExpectedIdentifier,
                "Expected identifier, found '{s}'",
                .{@tagName(self.current_token.type)}
            );
        }
        const token = self.current_token;
        try self.advance();
        return token;
    }

    fn advance(self: *Parser) !void {
        self.current_token = try self.tokenizer.next();
    }

    fn expect(self: *Parser, expected: TokenType) !void {
        if (self.current_token.type != expected) {
            // zig fmt: off
            return self.failWithContext(
                error.SyntaxError,
                "Expected '{s}', found '{s}'",
                .{@tagName(expected), @tagName(self.current_token.type)}
            );
        }

        try self.advance();
    }

    fn getPrecedence(self: *Parser) u8 {
        return switch (self.current_token.type) {
            .Star, .Slash, .Modulus => 7,
            .Plus, .Minus => 6,
            .Less, .LessEq, .Greater, .GreaterEq => 5,
            .EqEq, .NotEq => 4,
            .Pipe => 3,
            else => 0,
        };
    }

    fn validateType(self: *Parser, token_type: TokenType) !void {
        if (
            token_type != .TypeInt and
            token_type != .TypeFloat and
            token_type != .TypeBool and
            token_type != .TypeChar and
            token_type != .TypeString
        ) {
            // zig fmt: off
            return self.failWithContext(
                error.InvalidType,
                "'{s}' is not a valid type",
                .{self.current_token.value}
            );
        }
    }

    fn failWithContext(self: *Parser, err: ParserError, comptime fmt: []const u8, args: anytype) ParserError {
        const token = self.current_token;

        var line_start = token.start;
        while (line_start > 0 and self.tokenizer.source[line_start - 1] != '\n') {
            line_start -= 1;
        }
        var line_end = token.end;
        while (line_end < self.tokenizer.source.len and
            self.tokenizer.source[line_end] != '\n')
        {
            line_end += 1;
        }
        const error_line = self.tokenizer.source[line_start..line_end];

        // Calculate column position within this line
        const column_in_line = if (token.line == 1)
            token.column
        else
            token.column - 1;

        // Create padding matching the column position for the caret
        var padding_buf: [256]u8 = undefined;
        const padding_len = @min(column_in_line - 1, padding_buf.len);
        @memset(padding_buf[0..padding_len], ' ');
        const padding = padding_buf[0..padding_len];

        std.debug.print(
            \\[{s}] Error at line {d}:{d}
            \\{s}
            \\{s}^
            \\
        , .{
            @errorName(err),
            token.line,
            token.column,
            error_line,
            padding,
        });
        std.debug.print(fmt ++ "\n", args);

        return err;
    }
};
