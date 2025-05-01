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
    }
}

pub fn main() !void {
    const input =
        \\let x = 5
        \\let y: float = 2.5
        \\
        \\let add = fn(a: int, b: float) -> float { return a + b }
        \\let z = add(x, y)
        \\let a = return z
        \\return a
    ;
    std.debug.print("Input:\n{s}\n\n", .{input});

    var tokenizer = Tokenizer{ .source = input };
    var parser = try Parser.init(std.heap.page_allocator, &tokenizer);

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
        std.debug.print("\nOutput:\n{any}\n", .{vm.stack.items[0]});
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
