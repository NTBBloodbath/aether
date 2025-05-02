const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
// const lib = @import("aether");

const clap = @import("clap");

const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
const VM = @import("vm.zig").VM;

const Version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };

// Recursively print AST nodes for debugging
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
        .FunctionDecl => |f| {
            std.debug.print("FunctionDecl({s}, {s})\n", .{f.name, f.return_type});
            printExpr(f.body, indent + 1);
            for (f.params.items) |param| {
                var j: usize = 0;
                while (j < indent + 1) : (j += 1) {
                    std.debug.print("  ", .{});
                }
                const param_type = if (param.type_name == null) "inferred" else param.type_name.?;
                std.debug.print("Param({s}, {s})\n", .{param.name, param_type});
            }
        },
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
        .NilLiteral => std.debug.print("Nil(nil)\n", .{}),
        .CharLiteral => |c| {
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(c.value, &buf) catch return;
            std.debug.print("Char('{s}')\n", .{buf[0..len]});
        },
        .StringLiteral => |s| std.debug.print("String(\"{s}\")\n", .{s.value}),
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
                const param_type = if (param.type_name == null) "inferred" else param.type_name.?;
                std.debug.print("Param({s}, {s})\n", .{param.name, param_type});
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

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    // TODO: check for Aether's file extension
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Error opening '{s}': {s}\n", .{path, @errorName(err)});
        return err;
    };
    defer file.close();

    return file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch |err| {
        std.debug.print("Error reading '{s}': {s}\n", .{path, @errorName(err)});
        return err;
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    // Setup CLI
    const params = comptime clap.parseParamsComptime(
        \\-h, --help       Display this help and exit.
        \\-v, --version    Print version and exit.
        \\-e, --eval <str> Evaluate inline code.
        \\<str>            Script file to execute.
        \\
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try stdout.print("Usage: aether [OPTIONS] <SCRIPT>\n\n", .{});
        try bw.flush();

        try clap.help(stdout_file, clap.Help, &params, .{});
        return;
    }
    if (res.args.version != 0) {
        try stdout.print("Aether {d}.{d}.{d}\n", .{Version.major, Version.minor, Version.patch});
        try bw.flush();

        return;
    }

    // Get input source
    const input: []const u8 = if (res.positionals.len > 0)
        try readFile(allocator, res.positionals[0].?)
    else if (res.args.eval) |code|
        code
    else {
        try std.io.getStdErr().writer().print("Usage: aether [OPTIONS] <SCRIPT>\n\n", .{});

        try clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        std.process.exit(1);
    };

    var tokenizer = Tokenizer{ .source = input };
    var parser = try Parser.init(allocator, &tokenizer);

    const program = try parser.parseProgram();
    // std.debug.print("Parsed AST:\n", .{});
    // for (program.statements.items) |stmt| {
    //     printStatement(stmt, 0);
    // }

    var vm = try VM.init(std.heap.page_allocator);
    for (program.statements.items) |stmt| {
        try vm.eval(stmt);
    }

    if (vm.stack.items.len > 0) {
        // std.debug.print("\nOutput:\n", .{});
        try vm.stack.items[0].format("", .{}, stdout);
        try stdout.writeAll("\n");
    }

    try bw.flush();
}
