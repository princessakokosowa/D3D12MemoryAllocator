const std = @import("std");

fn concat(a: []const u8, b: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const result = try allocator.alloc(u8, a.len + b.len);

    std.mem.copy(u8, result, a);
    std.mem.copy(u8, result[a.len..], b);

    return result;
}

fn ascending(context: std.mem.Allocator, a: []const u8, b: []const u8) bool {
    _ = context;

    return std.mem.eql(u8, a, b);
}

fn findWindowsKitsAndAddItsLibraryPath(b: *std.build.Builder, lib: *std.Build.CompileStep) !void {
    // This is where Windows Kits has been for years, I don't mind if it's hardcoded.
    const windows_kits_lib_path = "C:\\Program Files (x86)\\Windows Kits\\10\\Lib";
    const um_subpath = "\\um\\x64";

    // Here, we hope to find _Windows Kits_ folder.
    var windows_kits_lib_dir = try std.fs.openIterableDirAbsolute(windows_kits_lib_path, .{
        .access_sub_paths = true,
    });

    var dirs = std.ArrayList([]const u8).init(b.allocator);
    defer dirs.deinit();

    // If it is found, there _must_ be a specific version of Windows Kits installed,
    // unless something is broken (either deliberately or not).
    //
    // In any case, we are trying to find the latest version here.
    var it = windows_kits_lib_dir.iterate();
    while (try it.next()) |dir| {
        if (dir.kind != .Directory) continue;

        try dirs.append(b.dupe(dir.name));
    }

    // If not found, exit here.
    if (dirs.getLastOrNull() == null) return error.NoVersionAvailable;

    // I am not sure whether we can rely on std library to automatically sort the
    // results for us (they may rely on Windows providing them the already sorted list
    // of directories), so we sort them ourselves.
    std.sort.sort([]const u8, dirs.items, b.allocator, ascending);

    const version = dirs.getLast();
    const version_subpath = try concat("\\", version, b.allocator);
    defer b.allocator.free(version_subpath);

    const windows_kits_lib_version_path = try concat(windows_kits_lib_path, version_subpath, b.allocator);
    defer b.allocator.free(windows_kits_lib_version_path);

    const windows_kits_lib_full_path = try concat(windows_kits_lib_version_path, um_subpath, b.allocator);
    defer b.allocator.free(windows_kits_lib_full_path);

    // Finally, we add Windows Kits to our library paths.
    lib.addLibraryPath(windows_kits_lib_full_path);
}

fn findWindowsKitsUserModeIncludePath(b: *std.build.Builder, lib: *std.Build.CompileStep) !void {
    // This is where Windows Kits has been for years, I don't mind if it's hardcoded.
    const windows_kits_include_path = "C:\\Program Files (x86)\\Windows Kits\\10\\Include";
    const subpaths = [_][]const u8 {
        "\\shared",
        "\\um",
        "\\winrt",
    };

    // Here, we hope to find _Windows Kits_ folder.
    var windows_kits_include_dir = try std.fs.openIterableDirAbsolute(windows_kits_include_path, .{
        .access_sub_paths = true,
    });

    var dirs = std.ArrayList([]const u8).init(b.allocator);
    defer dirs.deinit();

    // If it is found, there _must_ be a specific version of Windows Kits installed,
    // unless something is broken (either deliberately or not).
    //
    // In any case, we are trying to find the latest version here.
    var it = windows_kits_include_dir.iterate();
    while (try it.next()) |dir| {
        if (dir.kind != .Directory) continue;

        try dirs.append(b.dupe(dir.name));
    }

    // If not found, exit here.
    if (dirs.getLastOrNull() == null) return error.NoVersionAvailable;

    // I am not sure whether we can rely on std library to automatically sort the
    // results for us (they may rely on Windows providing them the already sorted list
    // of directories), so we sort them ourselves.
    std.sort.sort([]const u8, dirs.items, b.allocator, ascending);

    const version = dirs.getLast();
    const version_subpath = try concat("\\", version, b.allocator);
    defer b.allocator.free(version_subpath);

    const windows_kits_include_version_path = try concat(windows_kits_include_path,version_subpath, b.allocator);
    defer b.allocator.free(windows_kits_include_version_path);

    for (subpaths) |subpath| {
        const windows_kits_include_full_path = try concat(windows_kits_include_version_path, subpath, b.allocator);
        defer b.allocator.free(windows_kits_include_full_path);
    
        lib.addIncludePath(windows_kits_include_full_path);
    }
}

pub fn build(b: *std.Build) !void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "D3D12MA",
        .root_source_file = .{ .path = "src/D3D12MemAlloc.cpp" },
        .target = target,
        .optimize = optimize,
    });

    {
        lib.linkLibC();
        lib.linkLibCpp();

        // Apparently there is a bug regarding pkg-config (I have no idea what it is
        // exactly), which means we are using `linkSystemLibraryName()` instead of
        // `linkSystemLibrary()`.
        switch (lib.target.getOsTag()) {
            .windows => {
                try findWindowsKitsAndAddItsLibraryPath(b, lib);
                // try findWindowsKitsUserModeIncludePath(b, lib);

                lib.linkSystemLibraryName("d3d12");
                lib.linkSystemLibraryName("dxgi");
                lib.linkSystemLibraryName("dxguid");
            },
            // Yes, this means that you cannot compile this code on any operating system
            // other than Windows. Sorry.
            else => unreachable,
        }

        lib.addIncludePath("include");
        lib.addIncludePath("src");
        lib.addCSourceFiles(&.{
            "src/Common.cpp",
            "src/D3D12Sample.cpp",
            "src/Tests.cpp",
        }, &.{
            // Misc.
            "-Wno-unused-command-line-argument",
            "-std=c++14",
        });
    }

    b.installArtifact(lib);
}
