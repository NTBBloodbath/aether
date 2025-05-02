const std = @import("std");
const tokenizer = @import("tokenizer.zig");

pub const Program = struct {
    allocator: std.mem.Allocator,
    statements: std.ArrayList(*Statement),

    pub fn create(allocator: std.mem.Allocator) !*Program {
        const node = try allocator.create(Program);
        node.* = .{
            .allocator = allocator,
            .statements = std.ArrayList(*Statement).init(allocator),
        };
        return node;
    }

    pub fn deinit(self: *Program) void {
        for (self.statements.items) |stmt| {
            stmt.deinit(self.allocator);
        }
        self.allocator.destroy(self);
    }
};

pub const Statement = union(enum) {
    VariableDecl: *VariableDecl,
    Expr: *Expression,
    FunctionDecl: *FunctionDecl,
    Return: *ReturnStmt,

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .VariableDecl => |v| {
                v.value.deinit(allocator);
                allocator.destroy(v);
            },
            .Expr => |expr| expr.deinit(allocator),
            .FunctionDecl => |func| {
                func.params.deinit();
                func.body.deinit(allocator);
                allocator.destroy(func);
            },
            .Return => |ret| {
                ret.value.deinit(allocator);
                allocator.destroy(ret);
            },
        }
        allocator.destroy(self); // Also free the wrapper
    }
};

pub const ReturnStmt = struct {
    value: *Expression,

    pub fn create(allocator: std.mem.Allocator, ret: *Expression) !*Expression {
        const node = try allocator.create(ReturnStmt);
        node.* = .{ .value = ret };

        const expr = try allocator.create(Expression);
        expr.* = .{ .ReturnStmt = node };
        return expr;
    }
};

pub const Expression = union(enum) {
    NumberLiteral: *NumberLiteral,
    BooleanLiteral: *BooleanLiteral,
    NilLiteral: *NilLiteral,
    CharLiteral: *CharLiteral,
    StringLiteral: *StringLiteral,
    BinaryOp: *BinaryOp,
    VariableRef: *VariableRef,
    Lambda: *Lambda,
    FunctionCall: *FunctionCall,
    ReturnStmt: *ReturnStmt, // Allow return in expressions
    IfExpr: *IfExpr,

    pub fn deinit(self: *Expression, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .NumberLiteral => |n| {
                allocator.destroy(n);
            },
            .BooleanLiteral => |b| {
                allocator.destroy(b);
            },
            .NilLiteral => |n| {
                allocator.destroy(n);
            },
            .CharLiteral => |c| {
                allocator.destroy(c);
            },
            .StringLiteral => |s| {
                allocator.destroy(s);
            },
            .BinaryOp => |b| {
                b.left.deinit(allocator);
                b.right.deinit(allocator);
                allocator.destroy(b);
            },
            .VariableRef => |v| {
                allocator.destroy(v);
            },
            .Lambda => |l| {
                l.params.deinit();
                l.body.deinit(allocator);
                allocator.destroy(l);
            },
            .FunctionCall => |f| {
                f.callee.deinit(allocator);
                f.args.deinit();
                allocator.destroy(f);
            },
            .ReturnStmt => |ret| {
                ret.value.deinit(allocator);
                allocator.destroy(ret);
            },
            .IfExpr => |if_expr| {
                if_expr.condition.deinit(allocator);
                if_expr.then_branch.deinit(allocator);
                if (if_expr.else_branch) |else_expr| {
                    else_expr.deinit(allocator);
                }
            },
        }
        allocator.destroy(self); // Also free the wrapper
    }
};

pub const IfExpr = struct {
    condition: *Expression,
    then_branch: *Expression,
    else_branch: ?*Expression,

    pub fn create(allocator: std.mem.Allocator, condition: *Expression, then_branch: *Expression, else_branch: ?*Expression) !*Expression {
        const node = try allocator.create(IfExpr);
        node.* = .{ .condition = condition, .then_branch = then_branch, .else_branch = else_branch };

        const expr = try allocator.create(Expression);
        expr.* = .{ .IfExpr = node };
        return expr;
    }
};

pub const Param = struct {
    name: []const u8,
    type_name: ?[]const u8,
};

pub const Lambda = struct {
    params: std.ArrayList(Param),
    return_type: []const u8,
    body: *Expression,

    pub fn create(allocator: std.mem.Allocator, params: std.ArrayList(Param), return_type: []const u8, body: *Expression) !*Expression {
        const node = try allocator.create(Lambda);
        node.* = .{ .params = params, .return_type = return_type, .body = body };

        const expr = try allocator.create(Expression);
        expr.* = .{ .Lambda = node };
        return expr;
    }
};

pub const FunctionDecl = struct {
    name: []const u8,
    params: std.ArrayList(Param),
    return_type: []const u8,
    body: *Expression,

    pub fn create(allocator: std.mem.Allocator, name: []const u8, params: std.ArrayList(Param), return_type: []const u8, body: *Expression) !*Statement {
        const node = try allocator.create(FunctionDecl);
        node.* = .{ .name = name, .params = params, .return_type = return_type, .body = body };

        const stmt = try allocator.create(Statement);
        stmt.* = .{ .FunctionDecl = node };
        return stmt;
    }
};

pub const FunctionCall = struct {
    callee: *Expression,
    args: std.ArrayList(*Expression),

    pub fn create(allocator: std.mem.Allocator, callee: *Expression, args: std.ArrayList(*Expression)) !*Expression {
        const node = try allocator.create(FunctionCall);
        node.* = .{ .callee = callee, .args = args };

        const expr = try allocator.create(Expression);
        expr.* = .{ .FunctionCall = node };
        return expr;
    }
};

pub const NumberLiteral = struct {
    value: []const u8,

    pub fn create(value: []const u8, allocator: std.mem.Allocator) !*Expression {
        const node = try allocator.create(NumberLiteral);
        node.* = .{ .value = value };

        const expr = try allocator.create(Expression);
        expr.* = .{ .NumberLiteral = node };
        return expr;
    }
};

pub const BooleanLiteral = struct {
    value: bool,

    pub fn create(allocator: std.mem.Allocator, value: bool) !*Expression {
        const node = try allocator.create(BooleanLiteral);
        node.* = .{ .value = value };

        const expr = try allocator.create(Expression);
        expr.* = .{ .BooleanLiteral = node };
        return expr;
    }
};

pub const NilLiteral = struct {
    pub fn create(allocator: std.mem.Allocator) !*Expression {
        const node = try allocator.create(NilLiteral);

        const expr = try allocator.create(Expression);
        expr.* = .{ .NilLiteral = node };
        return expr;
    }
};

pub const CharLiteral = struct {
    value: u21, // Unicode code point

    pub fn create(allocator: std.mem.Allocator, value: u21) !*Expression {
        const node = try allocator.create(CharLiteral);
        node.* = .{ .value = value };

        const expr = try allocator.create(Expression);
        expr.* = .{ .CharLiteral = node };
        return expr;
    }
};

pub const StringLiteral = struct {
    value: []const u8,

    pub fn create(allocator: std.mem.Allocator, value: []const u8) !*Expression {
        const node = try allocator.create(StringLiteral);
        node.* = .{ .value = value };

        const expr = try allocator.create(Expression);
        expr.* = .{ .StringLiteral = node };
        return expr;
    }
};

pub const BinaryOp = struct {
    left: *Expression,
    op: tokenizer.Token,
    right: *Expression,

    pub fn create(
        allocator: std.mem.Allocator,
        left: *Expression,
        op: tokenizer.Token,
        right: *Expression,
    ) !*Expression {
        const node = try allocator.create(BinaryOp);
        node.* = .{ .left = left, .op = op, .right = right };

        const expr = try allocator.create(Expression);
        expr.* = .{ .BinaryOp = node };
        return expr;
    }
};

pub const VariableDecl = struct {
    name: []const u8,
    type_name: ?[]const u8, // null = inferred
    value: *Expression,

    pub fn create(allocator: std.mem.Allocator, name: []const u8, type_name: ?[]const u8, value: *Expression) !*Statement {
        const node = try allocator.create(VariableDecl);
        node.* = .{ .name = name, .type_name = type_name, .value = value };

        const expr = try allocator.create(Statement);
        expr.* = .{ .VariableDecl = node };
        return expr;
    }
};

pub const VariableRef = struct {
    name: []const u8,

    pub fn create(allocator: std.mem.Allocator, name: []const u8) !*Expression {
        const node = try allocator.create(VariableRef);
        node.* = .{ .name = name };

        const expr = try allocator.create(Expression);
        expr.* = .{ .VariableRef = node };
        return expr;
    }
};
