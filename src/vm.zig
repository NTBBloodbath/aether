const std = @import("std");

const ast = @import("ast.zig");

pub const Value = union(enum) {
    Int: i64,
    Float: f64,
    Bool: bool,
    Nil,
    Char: u21,
    String: []const u8,
    Function: *Closure,

    pub const Closure = struct {
        lambda: *ast.Lambda,
        env: *Environment,
    };

    // NOTE: unused atm, I no longer remember why I wrote this in first place
    pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .Int => |v| try writer.print("{d}", .{v}),
            .Float => |v| try writer.print("{d:.2}", .{v}),
            .Bool => |v| try writer.print("{s}", .{if (v) "true" else "false"}),
            .Nil => try writer.writeAll("nil"),
            .Char => |v| {
                var buf: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(v, &buf);
                try writer.print("'{s}'", .{std.unicode.fmtUtf8(buf[0..len])});
            },
            .String => |v| try writer.print("\"{s}\"", .{v}),
            else => try writer.print("{any}", .{self}),
        }
    }
};

pub const Environment = struct {
    parent: ?*Environment,
    values: std.StringHashMap(Value),

    pub fn create(allocator: std.mem.Allocator, parent: ?*Environment) !*Environment {
        const env = try allocator.create(Environment);
        env.* = .{
            .parent = parent,
            .values = std.StringHashMap(Value).init(allocator),
        };
        return env;
    }

    pub fn get(self: *Environment, key: []const u8) ?Value {
        return self.values.get(key) orelse if (self.parent) |p| p.get(key) else null;
    }
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    env: *Environment,
    stack: std.ArrayList(Value),

    pub fn init(allocator: std.mem.Allocator) !VM {
        const root_env = try Environment.create(allocator, null);
        return .{
            .allocator = allocator,
            .env = root_env,
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
                    const is_bool = std.mem.eql(u8, t, "bool") and value == .Bool;
                    const is_char = std.mem.eql(u8, t, "char") and value == .Char;
                    const is_str = std.mem.eql(u8, t, "string") and value == .String;
                    if (!is_float and !is_int and !is_bool and !is_char and !is_str) return error.TypeMismatch;
                }

                const variable = try self.env.values.getOrPut(v.name);
                if (variable.found_existing) {
                    return error.Redeclaration;
                }
                variable.value_ptr.* = value;
            },
            .Expr => |e| try self.eval_expr(e),
            .FunctionDecl => |func| {
                const closure_env = try Environment.create(self.allocator, self.env);

                const lambda = try self.allocator.create(ast.Lambda);
                lambda.* = .{
                    .params = func.params,
                    .return_type = func.return_type,
                    .body = func.body,
                };

                const closure = try self.allocator.create(Value.Closure);
                closure.* = .{
                    .lambda = lambda,
                    .env = closure_env,
                };

                try closure_env.values.put(func.name, .{ .Function = closure });
                try self.env.values.put(func.name, .{ .Function = closure });
            },
            .Return => |ret| try self.eval_expr(ret.value),
        }
    }

    fn eval_expr(self: *VM, node: *ast.Expression) !void {
        return switch (node.*) {
            .NumberLiteral => |n| {
                const value = try inferType(n.value);
                try self.stack.append(value);
            },
            .BooleanLiteral => |b| {
                // Convert the boolean into a string so we can infer the type
                const bool_type = switch (b.value) {
                    true => "true",
                    false => "false",
                };
                const value = try inferType(bool_type);
                try self.stack.append(value);
            },
            .NilLiteral => {
                try self.stack.append(.Nil);
            },
            .CharLiteral => |c| {
                // var buf: [4]u8 = undefined;
                // const len = try std.unicode.utf8Encode(c.value, &buf);
                // const value = try inferType(buf[0..len]);
                try self.stack.append(.{ .Char = c.value });
            },
            .StringLiteral => |s| {
                try self.stack.append(.{ .String = s.value });
            },
            .BinaryOp => |b| {
                try self.eval_expr(b.left);
                try self.eval_expr(b.right);
                const right = self.stack.pop().?;
                const left = self.stack.pop().?;
                const result = switch (b.op.type) {
                    .Plus => blk: {
                        // Concatenate Strings
                        // TODO: make use of a separate operator later for this to avoid ambiguity?
                        if (left == .String and right == .String) {
                            const new_str = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left.String, right.String });
                            break :blk Value{ .String = new_str };
                        }
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
                    .Modulus => blk: {
                        if (left == .Int and right == .Int) {
                            break :blk Value{ .Int = @rem(left.Int, right.Int) };
                        }
                        const lf = if (left == .Int) @as(f64, @floatFromInt(left.Int)) else left.Float;
                        const rf = if (right == .Int) @as(f64, @floatFromInt(right.Int)) else right.Float;
                        break :blk Value{ .Float = @rem(lf, rf) };
                    },
                    .EqEq => compareValues(left, right, .eq),
                    .NotEq => compareValues(left, right, .neq),
                    .Less => compareValues(left, right, .lt),
                    .LessEq => compareValues(left, right, .lte),
                    .Greater => compareValues(left, right, .gt),
                    .GreaterEq => compareValues(left, right, .gte),
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
                const closure_env = try Environment.create(self.allocator, self.env);

                const closure = try self.allocator.create(Value.Closure);
                closure.* = .{ .env = closure_env, .lambda = lambda };
                try self.stack.append(.{ .Function = closure });
            },
            .FunctionCall => |call| {
                try self.eval_expr(call.callee);
                const closure = self.stack.pop().?.Function;

                // Evaluate arguments
                var args = std.ArrayList(Value).init(self.allocator);
                for (call.args.items) |arg_expr| {
                    try self.eval_expr(arg_expr);
                    const arg_val = self.stack.pop().?;
                    try args.append(arg_val);

                    // Parameters type validation
                    const param = closure.lambda.params.items[args.items.len - 1];
                    try checkType(param.type_name, arg_val);
                }

                // Create nested environment for closure
                const call_env = try Environment.create(self.allocator, closure.env);

                // Bind parameters with shadowing
                for (closure.lambda.params.items, args.items) |param, arg| {
                    try call_env.values.put(param.name, arg);
                }

                // Execute in nested environment then restore current environment
                const prev_env = self.env;
                self.env = call_env;
                defer self.env = prev_env;

                // Evaluate function body
                try self.eval_expr(closure.lambda.body);
                const result = self.stack.pop().?;

                // Return type validation
                try checkType(closure.lambda.return_type, result);

                try self.stack.append(result);
            },
            .ReturnStmt => |ret| {
                try self.eval_expr(ret.value);
                const value = self.stack.pop().?;
                try self.stack.append(value);
            },
            .IfExpr => |if_expr| {
                try self.eval_expr(if_expr.condition);
                const cond_val = self.stack.pop().?;
                const is_true = switch (cond_val) {
                    .Int => |i| i != 0,
                    .Float => |f| f != 0.0,
                    .Bool => |b| b,
                    else => return error.TypeError,
                };

                if (is_true) {
                    try self.eval_expr(if_expr.then_branch);
                } else if (if_expr.else_branch) |else_expr| {
                    try self.eval_expr(else_expr);
                } else {
                    // Default to false
                    try self.stack.append(.{ .Bool = false });
                }
            },
        };
    }

    fn inferType(value: []const u8) !Value {
        // Handle boolean and nil literals
        if (std.mem.eql(u8, value, "true")) return .{ .Bool = true };
        if (std.mem.eql(u8, value, "false")) return .{ .Bool = false };
        if (std.mem.eql(u8, value, "nil")) return .Nil;

        // Handle numbers
        if (std.ascii.isDigit(value[0]) or value[0] == '-' or value[0] == '+') {
            if (std.mem.indexOf(u8, value, ".")) |_| {
                return .{ .Float = try std.fmt.parseFloat(f64, value) };
            } else {
                return .{ .Int = try std.fmt.parseInt(i64, value, 10) };
            }
        }

        // Should never reach here for valid literals (or so I hope)
        return error.CannotInferType;
    }

    fn getTypeName(val: Value) []const u8 {
        return switch (val) {
            .Int => "int",
            .Float => "float",
            .Bool => "bool",
            .Nil => "nil",
            .Char => "char",
            .String => "string",
            .Function => "function",
        };
    }

    fn checkType(expected: ?[]const u8, actual: Value) !void {
        if (expected) |exp| {
            if (!std.mem.eql(u8, exp, getTypeName(actual))) {
                return error.TypeMismatch;
            }
        }
    }

    fn compareValues(a: Value, b: Value, op: enum { eq, neq, lt, lte, gt, gte }) Value {
        const cmp = switch (a) {
            .Int => |a_val| switch (b) {
                .Int => |b_val| compare(a_val, b_val, op),
                .Float => |b_val| compare(@as(f64, @floatFromInt(a_val)), b_val, op),
                else => unreachable,
            },
            .Float => |a_val| switch (b) {
                .Int => |b_val| compare(a_val, @as(f64, @floatFromInt(b_val)), op),
                .Float => |b_val| compare(a_val, b_val, op),
                else => unreachable,
            },
            else => unreachable,
        };

        return .{ .Bool = cmp };
    }

    fn compare(a: anytype, b: anytype, op: anytype) bool {
        return switch (op) {
            .eq => a == b,
            .neq => a != b,
            .lt => a < b,
            .lte => a <= b,
            .gt => a > b,
            .gte => a >= b,
        };
    }
};
