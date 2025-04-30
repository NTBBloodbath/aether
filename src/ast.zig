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

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .VariableDecl => |v| {
                v.value.deinit(allocator);
                allocator.destroy(v);
            },
            .Expr => |expr| expr.deinit(allocator),
        }
        allocator.destroy(self); // Also free the wrapper
    }
};

pub const Expression = union(enum) {
    NumberLiteral: *NumberLiteral,
    BinaryOp: *BinaryOp,
    VariableRef: *VariableRef,

    pub fn deinit(self: *Expression, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .NumberLiteral => |n| {
                allocator.destroy(n);
            },
            .BinaryOp => |b| {
                b.left.deinit(allocator);
                b.right.deinit(allocator);
                allocator.destroy(b);
            },
            .VariableRef => |v| {
                allocator.destroy(v);
            },
        }
        allocator.destroy(self); // Also free the wrapper
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
