# MacOS

Zig bindings for macOS windowing: a Cocoa window whose view is backed by a
`CAMetalLayer`, to render into with Vulkan through MoltenVK (`VK_EXT_metal_surface`),
plus keyboard and mouse events.

| Namespace | Contents |
|-----------|----------|
| `OBJC`    | Objective-C runtime: `load`, `msgSend`, `sel`, `getClass` / `lookUpClass`, `respondsTo`, retain / release, `AutoreleasePool`, `ClassBuilder` |
| `APPKIT`  | `Application`, `Window`, `View`, `Screen`, `Event`, `MetalLayer`, `String`, `Date`, `Menu`, window delegate (`windowDelegate` + `WindowEvents`) |
| `TYPES`   | `NSRect` / `NSPoint` / `NSSize`, `WindowStyleMask`, `EventType`, `ModifierFlags`, `KeyCode`, ... |
| `DL`      | dlopen / dlsym helpers |

## Install

```sh
zig fetch --save git+https://github.com/Mauhlt/MacOS.git
```

```zig
const macos = b.dependency("MacOS", .{});
exe.root_module.addImport("MacOS", macos.module("MacOS"));
```

## Running on different macOS versions

Nothing is linked at build time. libobjc, Foundation, AppKit and QuartzCore are opened
with `dlopen` when you call `OBJC.load()`, so:

- it cross-compiles from Windows or Linux without the Apple SDK, and
- APIs newer than your minimum macOS can be feature-detected instead of failing at
  launch: `OBJC.lookUpClass("Name")` returns null for a missing class, and
  `OBJC.respondsTo(obj, OBJC.sel("method"))` checks for a method.
  `Application.activate` already does this.

`OBJC.msgSend` builds the exact C signature from the return and argument types. It uses
`objc_msgSend_stret` for struct returns larger than 16 bytes (`NSRect`) on Intel Macs,
as the x86_64 ABI requires, and plain `objc_msgSend` on Apple silicon.

## Example: window

```zig
const M = @import("MacOS");
const APPKIT = M.APPKIT;

try M.OBJC.load();
const app = APPKIT.Application.shared();
_ = app.setActivationPolicy(.regular);
app.installDefaultMenu("Renderer"); // Cmd+Q
app.finishLaunching();

const window = APPKIT.Window.create(.init(0, 0, 800, 600), .standard) orelse return error.Window;
defer M.OBJC.release(window);
window.setTitle("Renderer");
window.center();

var events: APPKIT.WindowEvents = .{};
const delegate = try APPKIT.windowDelegate(&events);
defer M.OBJC.release(delegate);
window.setDelegate(delegate);

// Vulkan: VkMetalSurfaceCreateInfoEXT{ .pLayer = layer }
const layer = window.contentView().?.useMetalLayer() orelse return error.NoMetal;
window.makeKeyAndOrderFront();
app.activate();

while (!events.close_requested) {
    const pool = M.OBJC.AutoreleasePool.push();
    defer pool.pop();
    while (app.nextEvent(.{})) |ev| {
        if (ev.kind() == .key_down and ev.keyCode() == .escape) events.close_requested = true;
        app.sendEvent(ev);
    }
    if (events.backing_changed) {
        layer.setContentsScale(window.backingScaleFactor());
        events.backing_changed = false;
    }
    // render a frame; size in pixels = view.convertRectToBacking(view.bounds())
}
window.close();
```

All AppKit calls must happen on the main thread.

## Tests

`zig build test` checks geometry layouts, flag bit values and the `msgSend` signature and
`stret` selection on any OS. `zig build test -Dtarget=aarch64-macos` (or `x86_64-macos`)
type-checks every binding for macOS from any machine. On a Mac the live tests also create
NSStrings, a window with a CAMetalLayer and a delegate. `zig build test-exe` installs the
test binary to copy to a Mac.
