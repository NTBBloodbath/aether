const std = @import("std");

const ast = @import("ast.zig");

const Token = @import("tokenizer.zig").Token;
const TokenType = @import("tokenizer.zig").TokenType;
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub const ParserError = error{
    UnexpectedToken,
    SyntaxError,
    InvalidCharacter, // Propagate tokenizer errors
    InvalidType,
    ExpectedIdentifier,
    OutOfMemory,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokenizer: *Tokenizer,
    current_token: Token,

    pub fn init(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ParserError!Parser {
        const first_token = try tokenizer.next();

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

    pub fn parseStatement(self: *Parser) !*ast.Statement {
        return switch (self.current_token.type) {
            .KeywordLet => blk: {
                const decl = try self.parseVariableDecl();
                const stmt = try self.allocator.create(ast.Statement);
                stmt.* = .{ .VariableDecl = decl };
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
        const left = try self.parsePrimary();

        return switch (self.current_token.type) {
            .Plus, .Minus, .Slash, .Star => {
                const op_token = self.current_token;
                try self.advance();
                const right = try self.parseExpression();

                return ast.BinaryOp.create(self.allocator, left, op_token, right);
            },
            else => left,
        };
    }

    fn parseLambda(self: *Parser) !*ast.Expression {
        // fn(param: type) -> return_type { ... }
        try self.expect(.KeywordFn);
        try self.expect(.LParen);

        var params = std.ArrayList(ast.Param).init(self.allocator);
        while (self.current_token.type != .RParen) {
            const name = try self.parseIdentifier();
            try self.expect(.Colon);
            const param_type = self.current_token.type;
            const type_name = self.current_token.value;
            try isValidType(param_type);
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
        try isValidType(return_type);
        try self.advance();

        // Parse body
        try self.expect(.LBrace);
        const body = try self.parseExpression();
        try self.expect(.RBrace);

        return ast.Lambda.create(self.allocator, params, return_type_name, body);
    }

    fn parseFunctionCall(self: *Parser, callee: *ast.Expression) !*ast.Expression {
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
            .KeywordFn => self.parseLambda(),
            else => ParserError.UnexpectedToken,
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
            try isValidType(token_type);
            try self.advance();
        }

        try self.expect(.Eq);
        const value = try self.parseExpression();
        const variable = try ast.VariableDecl.create(self.allocator, name.value, type_name, value);
        return variable.VariableDecl;
    }

    fn parseIdentifier(self: *Parser) !Token {
        if (self.current_token.type != .Identifier) {
            return ParserError.ExpectedIdentifier;
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
            return ParserError.SyntaxError;
        }

        try self.advance();
    }

    fn isValidType(token_type: TokenType) !void {
        if (token_type != .TypeInt and token_type != .TypeFloat) {
            return ParserError.InvalidType;
        }
    }
};
