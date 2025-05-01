const std = @import("std");

const ast = @import("ast.zig");

pub const Value = union(enum) {
    Int: i64,
    Float: f64,
    Function: *Closure,

    pub const Closure = struct {
        lambda: *ast.Lambda,
        env: std.StringHashMap(Value),
    };

    // NOTE: unused atm, I no longer remember why I wrote this in first place
    // pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    //     _ = fmt;
    //     _ = options;
    //     switch (self) {
    //         .Int => |v| try writer.print("{d}", .{v}),
    //         .Float => |v| try writer.print("{d:.2}", .{v}),
    //     }
    // }
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    env: std.StringHashMap(Value),
    stack: std.ArrayList(Value),

    pub fn init(allocator: std.mem.Allocator) VM {
        return .{
            .allocator = allocator,
            .env = std.StringHashMap(Value).init(allocator),
            .stack = std.ArrayList(Value).init(allocator),
        };
    }

    pub fn eval(self: *VM, node: *ast.Statement) !void {
        switch (node.*) {
            .VariableDecl => |v| {
                try self.eval_expr(v.value);
                const value = self.stack.pop().?;

                // Type validation
                if (v.type_name) |t| {
                    const is_float = std.mem.eql(u8, t, "float") and value == .Float;
                    const is_int = std.mem.eql(u8, t, "int") and value == .Int;
                    if (!is_float and !is_int) return error.TypeMismatch;
                }

                try self.env.put(v.name, value);
            },
            .Expr => |e| try self.eval_expr(e),
            .Return => |ret| try self.eval_expr(ret.value),
        }
    }

    fn eval_expr(self: *VM, node: *ast.Expression) !void {
        return switch (node.*) {
            .NumberLiteral => |n| {
                const value = try inferType(n.value);
                try self.stack.append(value);
            },
            .BinaryOp => |b| {
                try self.eval_expr(b.left);
                try self.eval_expr(b.right);
                const right = self.stack.pop().?;
                const left = self.stack.pop().?;
                const result = switch (b.op.type) {
                    .Plus => blk: {
                        if (left == .Int and right == .Int) {
                            break :blk Value{ .Int = left.Int + right.Int };
                        }
                        const lf = if (left == .Int) @as(f64, @floatFromInt(left.Int)) else left.Float;
                        const rf = if (right == .Int) @as(f64, @floatFromInt(right.Int)) else right.Float;
                        break :blk Value{ .Float = lf + rf };
                    },
                    .Minus => blk: {
                        if (left == .Int and right == .Int) {
                            break :blk Value{ .Int = left.Int - right.Int };
                        }
                        const lf = if (left == .Int) @as(f64, @floatFromInt(left.Int)) else left.Float;
                        const rf = if (right == .Int) @as(f64, @floatFromInt(right.Int)) else right.Float;
                        break :blk Value{ .Float = lf - rf };
                    },
                    .Slash => blk: {
                        if (left == .Int and right == .Int) {
                            break :blk Value{ .Int = @divExact(left.Int, right.Int) };
                        }
                        const lf = if (left == .Int) @as(f64, @floatFromInt(left.Int)) else left.Float;
                        const rf = if (right == .Int) @as(f64, @floatFromInt(right.Int)) else right.Float;
                        break :blk Value{ .Float = lf / rf };
                    },
                    .Star => blk: {
                        if (left == .Int and right == .Int) {
                            break :blk Value{ .Int = left.Int * right.Int };
                        }
                        const lf = if (left == .Int) @as(f64, @floatFromInt(left.Int)) else left.Float;
                        const rf = if (right == .Int) @as(f64, @floatFromInt(right.Int)) else right.Float;
                        break :blk Value{ .Float = lf * rf };
                    },
                    else => unreachable, // It should be impossible to reach this
                };
                try self.stack.append(result);
            },
            .VariableRef => |v| {
                const value = self.env.get(v.name) orelse return error.UndefinedVariable;
                try self.stack.append(value);
            },
            .Lambda => |lambda| {
                // Capture current environment
                const closure = try self.allocator.create(Value.Closure);
                closure.* = .{ .lambda = lambda, .env = self.env.clone() catch unreachable };
                try self.stack.append(.{ .Function = closure });
            },
            .FunctionCall => |call| {
                try self.eval_expr(call.callee);
                const closure = self.stack.pop().?.Function;

                // Evaluate arguments
                var args = std.ArrayList(Value).init(self.allocator);
                for (call.args.items) |arg_expr| {
                    try self.eval_expr(arg_expr);
                    try args.append(self.stack.pop().?);
                }

                // Push new scope
                const parent_env = self.env;
                self.env = closure.env.clone() catch unreachable;

                // Bind parameters
                for (closure.lambda.params.items, args.items) |param, arg| {
                    try self.env.put(param.name, arg);
                }

                // Evaluate body
                try self.eval_expr(closure.lambda.body);
                const result = self.stack.pop().?;

                // Restore environment
                self.env.deinit();
                self.env = parent_env;

                try self.stack.append(result);
            },
            .ReturnStmt => |ret| {
                try self.eval_expr(ret.value);
                const value = self.stack.pop().?;
                try self.stack.append(value);
            },
        };
    }

    fn inferType(value: []const u8) !Value {
        if (std.mem.indexOf(u8, value, ".")) |_| {
            return .{ .Float = try std.fmt.parseFloat(f64, value) };
        } else {
            return .{ .Int = try std.fmt.parseInt(i64, value, 10) };
        }
    }
};
