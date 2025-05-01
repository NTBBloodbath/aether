//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("aether");

const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
const VM = @import("vm.zig").VM;

// Recursively print AST nodes
fn printStatement(stmt: *ast.Statement, indent: usize) void {
    // HACK: I wanted to use ** but it requires comptime and fucks up the compilation
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        std.debug.print("  ", .{});
    }

    switch (stmt.*) {
        .VariableDecl => |decl| {
            const var_type = if (decl.type_name == null) "inferred" else decl.type_name.?;
            std.debug.print("VariableDecl({s}, {s})\n", .{ decl.name, var_type });
            printExpr(decl.value, indent + 1);
        },
        .Expr => |e| printExpr(e, indent),
        .Return => |ret| printExpr(ret.value, indent),
    }
}

fn printExpr(expr: *ast.Expression, indent: usize) void {
    // HACK: I wanted to use ** but it requires comptime and fucks up the compilation
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        std.debug.print("  ", .{});
    }

    switch (expr.*) {
        .NumberLiteral => |n| std.debug.print("Number({s})\n", .{n.value}),
        .BooleanLiteral => |b| std.debug.print("Boolean({any})\n", .{b.value}),
        .BinaryOp => |b| {
            std.debug.print("BinaryOp({s})\n", .{b.op.value});
            printExpr(b.left, indent + 1);
            printExpr(b.right, indent + 1);
        },
        .VariableRef => |ref| {
            std.debug.print("VariableRef({s})\n", .{ref.name});
        },
        .Lambda => |lambda| {
            std.debug.print("Lambda({s})\n", .{lambda.return_type});
            printExpr(lambda.body, indent + 1);
            for (lambda.params.items) |param| {
                var j: usize = 0;
                while (j < indent + 1) : (j += 1) {
                    std.debug.print("  ", .{});
                }
                std.debug.print("Param({s}, {s})\n", .{param.name, param.type_name});
            }
        },
        .FunctionCall => |call| {
            std.debug.print("FunctionCall\n", .{});
            printExpr(call.callee, indent + 1);
            for (call.args.items) |arg| {
                printExpr(arg, indent + 2);
            }
        },
        .ReturnStmt => |ret| {
            std.debug.print("Return\n", .{});
            printExpr(ret.value, indent + 1);
        },
        .IfExpr => |if_expr| {
            std.debug.print("IfExpr\n", .{});
            printExpr(if_expr.condition, indent + 1);
            printExpr(if_expr.then_branch, indent + 1);
            if (if_expr.else_branch) |else_expr| printExpr(else_expr, indent + 1);
        },
    }
}

pub fn main() !void {
    const input =
        // \\let factorial = fn(n: int) -> int {
        // \\    if n == 0 {
        // \\        1
        // \\    } else {
        // \\        n * factorial(n - 1)
        // \\    }
        // \\}
        // \\factorial(5)
        \\let is_even = fn(n: int) -> bool {
        \\    n % 2 == 0
        \\}
        \\is_even(4)
        // \\(4 % 2) == 0
    ;
    std.debug.print("Input:\n{s}\n\n", .{input});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = Tokenizer{ .source = input };
    var parser = try Parser.init(allocator, &tokenizer);

    const program = try parser.parseProgram();
    std.debug.print("Parsed AST:\n", .{});
    for (program.statements.items) |stmt| {
        printStatement(stmt, 0);
    }

    var vm = try VM.init(std.heap.page_allocator);
    for (program.statements.items) |stmt| {
        try vm.eval(stmt);
    }

    if (vm.stack.items.len < 1) {
        std.debug.print("\nOutput:\nNone\n", .{});
    } else {
        const stdout_file = std.io.getStdOut().writer();
        var bw = std.io.bufferedWriter(stdout_file);
        const stdout = bw.writer();

        std.debug.print("\nOutput:\n", .{});
        try vm.stack.items[0].format("", .{}, stdout);

        try bw.flush(); // Don't forget to flush!
    }

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();
    //
    // try stdout.print("Run `zig build test` to run the tests.\n", .{});
    //
    // try bw.flush(); // Don't forget to flush!
}
