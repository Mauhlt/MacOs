const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // libc is only needed for dlopen; libobjc and the frameworks are loaded at runtime.
    const mod = b.addModule("MacOS", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const mod_tests = b.addTest(.{ .root_module = mod, .name = "macos-test" });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    // `zig build test -Dtarget=aarch64-macos` from another OS still compiles and links the tests.
    run_mod_tests.skip_foreign_checks = true;
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // Installs zig-out/bin/macos-test, e.g. to copy to a Mac and run there.
    const install_tests = b.addInstallArtifact(mod_tests, .{});
    const test_exe_step = b.step("test-exe", "Install the test binary");
    test_exe_step.dependOn(&install_tests.step);
}
