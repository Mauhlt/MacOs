//! Zig bindings for macOS windowing: a Cocoa window with a CAMetalLayer to render into with
//! Vulkan (MoltenVK, VK_EXT_metal_surface), plus input.
//!
//!     const M = @import("MacOS");
//!     try M.OBJC.load();                       // dlopens libobjc + AppKit + QuartzCore
//!     const app = M.APPKIT.Application.shared();
//!
//! Nothing is linked at build time, so the package cross-compiles from Windows / Linux, and
//! newer-macOS classes or methods can be feature-detected (`OBJC.lookUpClass`, `OBJC.respondsTo`).

pub const OBJC = @import("objc.zig");
pub const TYPES = @import("macos_types.zig");
pub const APPKIT = @import("appkit.zig");
pub const DL = @import("dl.zig");

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

/// Forces semantic analysis of every declaration (and nested type methods).
fn refAllDeclsRecursive(comptime T: type, comptime depth: u32) void {
    if (depth == 0) return;
    inline for (comptime std.meta.declarations(T)) |name| {
        const field = @field(T, name);
        if (@TypeOf(field) == type) {
            switch (@typeInfo(field)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(field, depth - 1),
                else => {},
            }
        }
        _ = &field;
    }
}

test "analyze all declarations (macOS targets)" {
    // Only meaningful when building for macOS (e.g. `zig build test -Dtarget=aarch64-macos`).
    if (!builtin.os.tag.isDarwin()) return error.SkipZigTest;
    refAllDeclsRecursive(@This(), 4);
}

test "geometry types match CoreGraphics (64-bit)" {
    try testing.expectEqual(16, @sizeOf(TYPES.NSPoint));
    try testing.expectEqual(16, @sizeOf(TYPES.NSSize));
    try testing.expectEqual(32, @sizeOf(TYPES.NSRect));
    try testing.expectEqual(16, @offsetOf(TYPES.NSRect, "size"));
    try testing.expectEqual(1, @sizeOf(OBJC.BOOL));
}

test "flag sets have the SDK bit values" {
    const u = struct {
        fn v(x: anytype) u64 {
            return @bitCast(x);
        }
    }.v;
    try testing.expectEqual(0xF, u(TYPES.WindowStyleMask.standard));
    try testing.expectEqual(1 << 15, u(TYPES.WindowStyleMask{ .full_size_content_view = true }));
    try testing.expectEqual(1 << 14, u(TYPES.WindowStyleMask{ .full_screen = true }));
    try testing.expectEqual(1 << 12, u(TYPES.WindowStyleMask{ .unified_title_and_toolbar = true }));
    try testing.expectEqual(1 << 17, u(TYPES.ModifierFlags{ .shift = true }));
    try testing.expectEqual(1 << 20, u(TYPES.ModifierFlags{ .command = true }));
    try testing.expectEqual(1 << 23, u(TYPES.ModifierFlags{ .function = true }));
    try testing.expectEqual(10, @backingInt(TYPES.EventType.key_down));
    try testing.expectEqual(22, @backingInt(TYPES.EventType.scroll_wheel));
    try testing.expectEqual(2, @backingInt(TYPES.BackingStoreType.buffered));
    try testing.expectEqual(0x35, @backingInt(TYPES.KeyCode.escape));
    try testing.expectEqual(0x7E, @backingInt(TYPES.KeyCode.up_arrow));
    try testing.expectEqual(0x0D, @backingInt(TYPES.KeyCode.w));
}

test "msgSend picks objc_msgSend_stret only for large struct returns on x86_64" {
    try testing.expect(OBJC.usesStret(.x86_64, TYPES.NSRect));
    try testing.expect(!OBJC.usesStret(.x86_64, TYPES.NSPoint));
    try testing.expect(!OBJC.usesStret(.x86_64, TYPES.NSSize));
    try testing.expect(!OBJC.usesStret(.x86_64, f64));
    try testing.expect(!OBJC.usesStret(.aarch64, TYPES.NSRect));

    // The generated C signature: (id, SEL, args...) -> Ret.
    const F = OBJC.MsgSendFn(TYPES.NSRect, struct { TYPES.NSRect, u64 });
    const info = @typeInfo(F).@"fn";
    try testing.expectEqual(4, info.param_types.len);
    try testing.expectEqual(?*OBJC.Object, info.param_types[0].?);
    try testing.expectEqual(*OBJC.Selector, info.param_types[1].?);
    try testing.expectEqual(TYPES.NSRect, info.param_types[2].?);
    try testing.expectEqual(TYPES.NSRect, info.return_type.?);
}

// --- Live tests: need a Mac ------------------------------------------------------

test "live: Objective-C runtime round trips" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    try OBJC.load();
    const pool = OBJC.AutoreleasePool.push();
    defer pool.pop();

    const s = APPKIT.String.fromUtf8("h\u{e9}llo zig") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("h\u{e9}llo zig", std.mem.span(s.utf8().?));
    try testing.expectEqual(9, s.length());
    const kept = OBJC.retain(s);
    OBJC.release(kept);
    _ = OBJC.autorelease(OBJC.retain(s));
    try testing.expect(OBJC.lookUpClass("ZigNoSuchClass") == null);
    try testing.expect(OBJC.respondsTo(s, OBJC.sel("length")));
    try testing.expect(!OBJC.respondsTo(s, OBJC.sel("zigNoSuchMethod")));
    try testing.expectEqualStrings("kCFRunLoopDefaultMode", std.mem.span(APPKIT.defaultRunLoopMode().utf8().?));
}

test "live: window with a CAMetalLayer and a delegate" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    try OBJC.load();
    const pool = OBJC.AutoreleasePool.push();
    defer pool.pop();

    const app = APPKIT.Application.shared();
    try testing.expect(app.setActivationPolicy(.regular));
    app.installDefaultMenu("ZigTest");
    app.finishLaunching();

    const window = APPKIT.Window.create(.init(100, 100, 640, 480), .standard) orelse return error.TestUnexpectedResult;
    defer OBJC.release(window);
    window.setTitle("Zig macOS bindings test");

    var events: APPKIT.WindowEvents = .{};
    const delegate = try APPKIT.windowDelegate(&events);
    defer OBJC.release(delegate);
    window.setDelegate(delegate);
    defer window.setDelegate(null);

    const layer = window.contentView().?.useMetalLayer() orelse return error.SkipZigTest; // no Metal
    try testing.expectEqual(window.backingScaleFactor(), layer.contentsScale());
    const content = window.contentRectForFrameRect(window.frame());
    try testing.expectEqual(640, content.size.width);
    try testing.expectEqual(480, window.contentView().?.bounds().size.height);

    window.makeKeyAndOrderFront();
    while (app.nextEvent(.{})) |ev| app.sendEvent(ev);
    try testing.expect(window.isVisible());

    // Drive the delegate the way AppKit does when the close button is clicked.
    _ = OBJC.msgSend(OBJC.BOOL, delegate, OBJC.sel("windowShouldClose:"), .{@as(?*OBJC.Object, @ptrCast(window))});
    try testing.expect(events.close_requested);
    window.close();
}
