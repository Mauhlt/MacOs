//! AppKit / Foundation / QuartzCore objects a renderer needs: an app, a window, a view backed by
//! a CAMetalLayer (for Vulkan via MoltenVK's VK_EXT_metal_surface), events and screens.
//!
//!     try OBJC.load();
//!     const app = APPKIT.Application.shared();
//!     _ = app.setActivationPolicy(.regular);
//!     const window = APPKIT.Window.create(.init(0, 0, 800, 600), .standard) orelse return error.Window;
//!     var events: APPKIT.WindowEvents = .{};
//!     window.setDelegate(try APPKIT.windowDelegate(&events));
//!     const layer = window.contentView().?.useMetalLayer() orelse return error.Layer; // -> Vulkan
//!     window.makeKeyAndOrderFront();
//!     app.finishLaunching();
//!     while (!events.close_requested) {
//!         const pool = OBJC.AutoreleasePool.push();
//!         defer pool.pop();
//!         while (app.nextEvent(.{ .wait = false })) |ev| app.sendEvent(ev);
//!         // render
//!     }
//!
//! All AppKit calls must happen on the main thread.
const std = @import("std");
const objc = @import("objc.zig");
const T = @import("macos_types.zig");

const Object = objc.Object;
const msgSend = objc.msgSend;
const sel = objc.sel;
const NSRect = T.NSRect;
const NSSize = T.NSSize;
const NSPoint = T.NSPoint;
const CGFloat = T.CGFloat;

// ---------------------------------------------------------------------------
// Foundation
// ---------------------------------------------------------------------------

pub const String = opaque {
    /// Autoreleased NSString copy of `text`.
    pub fn fromUtf8(text: [*:0]const u8) ?*String {
        return msgSend(?*String, objc.getClass("NSString"), sel("stringWithUTF8String:"), .{text});
    }
    /// Valid while the string (or the current autorelease pool) lives.
    pub fn utf8(self: *String) ?[*:0]const u8 {
        return msgSend(?[*:0]const u8, self, sel("UTF8String"), .{});
    }
    /// Length in UTF-16 code units.
    pub fn length(self: *String) usize {
        return msgSend(T.NSUInteger, self, sel("length"), .{});
    }
};

pub const Date = opaque {
    pub fn distantPast() *Date {
        return msgSend(*Date, objc.getClass("NSDate"), sel("distantPast"), .{});
    }
    pub fn distantFuture() *Date {
        return msgSend(*Date, objc.getClass("NSDate"), sel("distantFuture"), .{});
    }
};

/// NSDefaultRunLoopMode.
pub fn defaultRunLoopMode() *String {
    if (objc.frameworkSymbol(*String, "NSDefaultRunLoopMode")) |p| return p.*;
    // Same value the constant holds.
    return String.fromUtf8("kCFRunLoopDefaultMode").?;
}

// ---------------------------------------------------------------------------
// NSApplication
// ---------------------------------------------------------------------------

pub const Application = opaque {
    /// The shared NSApplication (creates it on first call).
    pub fn shared() *Application {
        return msgSend(*Application, objc.getClass("NSApplication"), sel("sharedApplication"), .{});
    }
    pub fn setActivationPolicy(self: *Application, policy: T.ActivationPolicy) bool {
        return msgSend(objc.BOOL, self, sel("setActivationPolicy:"), .{policy}) != 0;
    }
    /// Brings the app to the front.
    pub fn activate(self: *Application) void {
        // `activate` is macOS 14+; `activateIgnoringOtherApps:` works everywhere (deprecated in 14).
        if (objc.respondsTo(self, sel("activate")))
            msgSend(void, self, sel("activate"), .{})
        else
            msgSend(void, self, sel("activateIgnoringOtherApps:"), .{objc.YES});
    }
    /// Call once before polling events yourself (instead of `run`).
    pub fn finishLaunching(self: *Application) void {
        msgSend(void, self, sel("finishLaunching"), .{});
    }
    /// Blocks in AppKit's own loop until `stop` / `terminate`.
    pub fn run(self: *Application) void {
        msgSend(void, self, sel("run"), .{});
    }
    pub fn stop(self: *Application) void {
        msgSend(void, self, sel("stop:"), .{@as(?*Object, null)});
    }
    pub fn terminate(self: *Application) void {
        msgSend(void, self, sel("terminate:"), .{@as(?*Object, null)});
    }

    pub const NextEventOptions = struct {
        /// false = return immediately (poll), true = block until an event arrives.
        wait: bool = false,
        mask: u64 = T.event_mask_any,
    };
    /// Dequeues the next event (autoreleased). Pass it on with `sendEvent`.
    pub fn nextEvent(self: *Application, options: NextEventOptions) ?*Event {
        const until = if (options.wait) Date.distantFuture() else Date.distantPast();
        return msgSend(?*Event, self, sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), .{
            options.mask, until, defaultRunLoopMode(), objc.YES,
        });
    }
    pub fn sendEvent(self: *Application, event: *Event) void {
        msgSend(void, self, sel("sendEvent:"), .{event});
    }
    pub fn updateWindows(self: *Application) void {
        msgSend(void, self, sel("updateWindows"), .{});
    }
    pub fn setMainMenu(self: *Application, menu: *Menu) void {
        msgSend(void, self, sel("setMainMenu:"), .{menu});
    }
    /// Installs a minimal menu bar with "Quit <app_name>" (Cmd+Q).
    pub fn installDefaultMenu(self: *Application, app_name: [*:0]const u8) void {
        const bar = Menu.create();
        const app_item = MenuItem.create("", null, "");
        bar.addItem(app_item);
        const app_menu = Menu.create();
        var buf: [256]u8 = undefined;
        const title = std.fmt.bufPrintSentinel(&buf, "Quit {s}", .{app_name}, 0) catch "Quit";
        app_menu.addItem(MenuItem.create(title, sel("terminate:"), "q"));
        app_item.setSubmenu(app_menu);
        self.setMainMenu(bar);
        objc.release(app_menu);
        objc.release(app_item);
        objc.release(bar);
    }
};

pub const Menu = opaque {
    /// +1 retained.
    pub fn create() *Menu {
        const m = msgSend(*Menu, objc.getClass("NSMenu"), sel("alloc"), .{});
        return msgSend(*Menu, m, sel("init"), .{});
    }
    pub fn addItem(self: *Menu, item: *MenuItem) void {
        msgSend(void, self, sel("addItem:"), .{item});
    }
};

pub const MenuItem = opaque {
    /// +1 retained. `key` is the key equivalent ("q" = Cmd+Q, "" = none).
    pub fn create(title: [*:0]const u8, action: ?*objc.Selector, key: [*:0]const u8) *MenuItem {
        const i = msgSend(*MenuItem, objc.getClass("NSMenuItem"), sel("alloc"), .{});
        return msgSend(*MenuItem, i, sel("initWithTitle:action:keyEquivalent:"), .{
            String.fromUtf8(title).?, action, String.fromUtf8(key).?,
        });
    }
    pub fn setSubmenu(self: *MenuItem, menu: *Menu) void {
        msgSend(void, self, sel("setSubmenu:"), .{menu});
    }
};

// ---------------------------------------------------------------------------
// NSWindow / NSView / NSScreen
// ---------------------------------------------------------------------------

pub const Window = opaque {
    /// +1 retained window with `content_rect` in screen points (bottom-left origin).
    pub fn create(content_rect: NSRect, style: T.WindowStyleMask) ?*Window {
        const w = msgSend(?*Window, objc.getClass("NSWindow"), sel("alloc"), .{}) orelse return null;
        const win = msgSend(?*Window, w, sel("initWithContentRect:styleMask:backing:defer:"), .{
            content_rect, style, T.BackingStoreType.buffered, objc.NO,
        }) orelse return null;
        // We own the reference; don't let -close free it behind our back.
        win.setReleasedWhenClosed(false);
        return win;
    }
    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        msgSend(void, self, sel("setTitle:"), .{String.fromUtf8(title).?});
    }
    pub fn makeKeyAndOrderFront(self: *Window) void {
        msgSend(void, self, sel("makeKeyAndOrderFront:"), .{@as(?*Object, null)});
    }
    pub fn orderOut(self: *Window) void {
        msgSend(void, self, sel("orderOut:"), .{@as(?*Object, null)});
    }
    pub fn center(self: *Window) void {
        msgSend(void, self, sel("center"), .{});
    }
    pub fn close(self: *Window) void {
        msgSend(void, self, sel("close"), .{});
    }
    pub fn setReleasedWhenClosed(self: *Window, released: bool) void {
        msgSend(void, self, sel("setReleasedWhenClosed:"), .{objc.toBOOL(released)});
    }
    pub fn setDelegate(self: *Window, delegate: ?*Object) void {
        msgSend(void, self, sel("setDelegate:"), .{delegate});
    }
    pub fn contentView(self: *Window) ?*View {
        return msgSend(?*View, self, sel("contentView"), .{});
    }
    pub fn setContentView(self: *Window, view: *View) void {
        msgSend(void, self, sel("setContentView:"), .{view});
    }
    /// Frame including the title bar, in screen points.
    pub fn frame(self: *Window) NSRect {
        return msgSend(NSRect, self, sel("frame"), .{});
    }
    pub fn contentRectForFrameRect(self: *Window, rect: NSRect) NSRect {
        return msgSend(NSRect, self, sel("contentRectForFrameRect:"), .{rect});
    }
    pub fn setContentSize(self: *Window, size: NSSize) void {
        msgSend(void, self, sel("setContentSize:"), .{size});
    }
    pub fn setContentMinSize(self: *Window, size: NSSize) void {
        msgSend(void, self, sel("setContentMinSize:"), .{size});
    }
    /// Pixels per point (2.0 on Retina).
    pub fn backingScaleFactor(self: *Window) CGFloat {
        return msgSend(CGFloat, self, sel("backingScaleFactor"), .{});
    }
    pub fn convertRectToBacking(self: *Window, rect: NSRect) NSRect {
        return msgSend(NSRect, self, sel("convertRectToBacking:"), .{rect});
    }
    pub fn setAcceptsMouseMovedEvents(self: *Window, accepts: bool) void {
        msgSend(void, self, sel("setAcceptsMouseMovedEvents:"), .{objc.toBOOL(accepts)});
    }
    pub fn makeFirstResponder(self: *Window, responder: ?*Object) bool {
        return msgSend(objc.BOOL, self, sel("makeFirstResponder:"), .{responder}) != 0;
    }
    pub fn toggleFullScreen(self: *Window) void {
        msgSend(void, self, sel("toggleFullScreen:"), .{@as(?*Object, null)});
    }
    pub fn isVisible(self: *Window) bool {
        return msgSend(objc.BOOL, self, sel("isVisible"), .{}) != 0;
    }
    pub fn isKeyWindow(self: *Window) bool {
        return msgSend(objc.BOOL, self, sel("isKeyWindow"), .{}) != 0;
    }
    pub fn isMiniaturized(self: *Window) bool {
        return msgSend(objc.BOOL, self, sel("isMiniaturized"), .{}) != 0;
    }
    pub fn screen(self: *Window) ?*Screen {
        return msgSend(?*Screen, self, sel("screen"), .{});
    }
};

pub const View = opaque {
    /// Bounds in points.
    pub fn bounds(self: *View) NSRect {
        return msgSend(NSRect, self, sel("bounds"), .{});
    }
    pub fn frame(self: *View) NSRect {
        return msgSend(NSRect, self, sel("frame"), .{});
    }
    /// Points -> pixels.
    pub fn convertRectToBacking(self: *View, rect: NSRect) NSRect {
        return msgSend(NSRect, self, sel("convertRectToBacking:"), .{rect});
    }
    pub fn setWantsLayer(self: *View, wants: bool) void {
        msgSend(void, self, sel("setWantsLayer:"), .{objc.toBOOL(wants)});
    }
    pub fn setLayer(self: *View, new_layer: ?*Object) void {
        msgSend(void, self, sel("setLayer:"), .{new_layer});
    }
    pub fn layer(self: *View) ?*Object {
        return msgSend(?*Object, self, sel("layer"), .{});
    }
    pub fn window(self: *View) ?*Window {
        return msgSend(?*Window, self, sel("window"), .{});
    }
    /// Makes this view layer-hosting with a new CAMetalLayer at the window's scale.
    /// The returned layer (owned by the view) is what VK_EXT_metal_surface needs.
    pub fn useMetalLayer(self: *View) ?*MetalLayer {
        const l = MetalLayer.create() orelse return null;
        self.setLayer(@ptrCast(l));
        self.setWantsLayer(true);
        if (self.window()) |w| l.setContentsScale(w.backingScaleFactor());
        objc.release(l); // the view holds it now
        return l;
    }
};

pub const Screen = opaque {
    pub fn main() ?*Screen {
        return msgSend(?*Screen, objc.getClass("NSScreen"), sel("mainScreen"), .{});
    }
    pub fn frame(self: *Screen) NSRect {
        return msgSend(NSRect, self, sel("frame"), .{});
    }
    /// Frame minus the menu bar and Dock.
    pub fn visibleFrame(self: *Screen) NSRect {
        return msgSend(NSRect, self, sel("visibleFrame"), .{});
    }
    pub fn backingScaleFactor(self: *Screen) CGFloat {
        return msgSend(CGFloat, self, sel("backingScaleFactor"), .{});
    }
};

// ---------------------------------------------------------------------------
// CAMetalLayer (QuartzCore)
// ---------------------------------------------------------------------------

pub const MetalLayer = opaque {
    /// +1 retained. Null on Macs without Metal.
    pub fn create() ?*MetalLayer {
        const cls = objc.lookUpClass("CAMetalLayer") orelse return null;
        return msgSend(?*MetalLayer, cls, sel("new"), .{});
    }
    pub fn setContentsScale(self: *MetalLayer, scale: CGFloat) void {
        msgSend(void, self, sel("setContentsScale:"), .{scale});
    }
    pub fn contentsScale(self: *MetalLayer) CGFloat {
        return msgSend(CGFloat, self, sel("contentsScale"), .{});
    }
    /// In pixels. MoltenVK sets this from the swapchain extent.
    pub fn setDrawableSize(self: *MetalLayer, size: NSSize) void {
        msgSend(void, self, sel("setDrawableSize:"), .{size});
    }
    pub fn drawableSize(self: *MetalLayer) NSSize {
        return msgSend(NSSize, self, sel("drawableSize"), .{});
    }
    pub fn asObject(self: *MetalLayer) *Object {
        return @ptrCast(self);
    }
};

// ---------------------------------------------------------------------------
// NSEvent
// ---------------------------------------------------------------------------

pub const Event = opaque {
    pub fn kind(self: *Event) T.EventType {
        return msgSend(T.EventType, self, sel("type"), .{});
    }
    pub fn window(self: *Event) ?*Window {
        return msgSend(?*Window, self, sel("window"), .{});
    }
    /// Key events only.
    pub fn keyCode(self: *Event) T.KeyCode {
        return msgSend(T.KeyCode, self, sel("keyCode"), .{});
    }
    pub fn isARepeat(self: *Event) bool {
        return msgSend(objc.BOOL, self, sel("isARepeat"), .{}) != 0;
    }
    /// Text the key produced (key events only).
    pub fn characters(self: *Event) ?*String {
        return msgSend(?*String, self, sel("characters"), .{});
    }
    pub fn charactersIgnoringModifiers(self: *Event) ?*String {
        return msgSend(?*String, self, sel("charactersIgnoringModifiers"), .{});
    }
    pub fn modifierFlags(self: *Event) T.ModifierFlags {
        return msgSend(T.ModifierFlags, self, sel("modifierFlags"), .{});
    }
    /// Mouse position in window points (bottom-left origin).
    pub fn locationInWindow(self: *Event) NSPoint {
        return msgSend(NSPoint, self, sel("locationInWindow"), .{});
    }
    /// 0 left, 1 right, 2 middle, 3+ extra buttons.
    pub fn buttonNumber(self: *Event) T.NSInteger {
        return msgSend(T.NSInteger, self, sel("buttonNumber"), .{});
    }
    pub fn clickCount(self: *Event) T.NSInteger {
        return msgSend(T.NSInteger, self, sel("clickCount"), .{});
    }
    /// Relative mouse motion (also while the cursor is pinned).
    pub fn deltaX(self: *Event) CGFloat {
        return msgSend(CGFloat, self, sel("deltaX"), .{});
    }
    pub fn deltaY(self: *Event) CGFloat {
        return msgSend(CGFloat, self, sel("deltaY"), .{});
    }
    pub fn scrollingDeltaX(self: *Event) CGFloat {
        return msgSend(CGFloat, self, sel("scrollingDeltaX"), .{});
    }
    pub fn scrollingDeltaY(self: *Event) CGFloat {
        return msgSend(CGFloat, self, sel("scrollingDeltaY"), .{});
    }
    /// True for trackpads (pixel deltas), false for wheel lines.
    pub fn hasPreciseScrollingDeltas(self: *Event) bool {
        return msgSend(objc.BOOL, self, sel("hasPreciseScrollingDeltas"), .{}) != 0;
    }
};

// ---------------------------------------------------------------------------
// Window delegate: turns NSWindowDelegate callbacks into flags you poll
// ---------------------------------------------------------------------------

/// Set by the delegate from `windowDelegate`; clear the ones you've handled.
pub const WindowEvents = struct {
    /// The user clicked the close button / pressed Cmd+W. The window stays open until you close it.
    close_requested: bool = false,
    resized: bool = false,
    /// Moved to a screen with a different scale; update the layer's contentsScale.
    backing_changed: bool = false,
    focused: bool = false,
    focus_changed: bool = false,
    miniaturized: bool = false,
};

const delegate_class_name = "ZigMacOSWindowDelegate";
const events_ivar = "zig_events";

fn eventsOf(self: *Object) *WindowEvents {
    return objc.ivarPtr(*WindowEvents, self, events_ivar).*;
}

const DelegateImpl = struct {
    fn shouldClose(self: *Object, _: *objc.Selector, _: ?*Object) callconv(.c) objc.BOOL {
        eventsOf(self).close_requested = true;
        return objc.NO;
    }
    fn didResize(self: *Object, _: *objc.Selector, _: ?*Object) callconv(.c) void {
        eventsOf(self).resized = true;
    }
    fn didChangeBacking(self: *Object, _: *objc.Selector, _: ?*Object) callconv(.c) void {
        eventsOf(self).backing_changed = true;
    }
    fn didBecomeKey(self: *Object, _: *objc.Selector, _: ?*Object) callconv(.c) void {
        const ev = eventsOf(self);
        ev.focused = true;
        ev.focus_changed = true;
    }
    fn didResignKey(self: *Object, _: *objc.Selector, _: ?*Object) callconv(.c) void {
        const ev = eventsOf(self);
        ev.focused = false;
        ev.focus_changed = true;
    }
    fn didMiniaturize(self: *Object, _: *objc.Selector, _: ?*Object) callconv(.c) void {
        eventsOf(self).miniaturized = true;
    }
    fn didDeminiaturize(self: *Object, _: *objc.Selector, _: ?*Object) callconv(.c) void {
        eventsOf(self).miniaturized = false;
    }
};

fn delegateClass() *objc.Class {
    if (objc.lookUpClassUncached(delegate_class_name)) |cls| return cls;
    const b = objc.ClassBuilder.begin(objc.getClass("NSObject"), delegate_class_name) orelse
        return objc.lookUpClassUncached(delegate_class_name).?;
    _ = b.addIvar(events_ivar, *WindowEvents, "^v");
    _ = b.addMethod("windowShouldClose:", &DelegateImpl.shouldClose, "c@:@");
    _ = b.addMethod("windowDidResize:", &DelegateImpl.didResize, "v@:@");
    _ = b.addMethod("windowDidChangeBackingProperties:", &DelegateImpl.didChangeBacking, "v@:@");
    _ = b.addMethod("windowDidBecomeKey:", &DelegateImpl.didBecomeKey, "v@:@");
    _ = b.addMethod("windowDidResignKey:", &DelegateImpl.didResignKey, "v@:@");
    _ = b.addMethod("windowDidMiniaturize:", &DelegateImpl.didMiniaturize, "v@:@");
    _ = b.addMethod("windowDidDeminiaturize:", &DelegateImpl.didDeminiaturize, "v@:@");
    return b.register();
}

/// A +1 retained NSWindowDelegate that records events into `events` (which must outlive it).
/// Pass to `Window.setDelegate`; release after clearing the window's delegate.
pub fn windowDelegate(events: *WindowEvents) error{OutOfMemory}!*Object {
    const obj = msgSend(?*Object, delegateClass(), sel("new"), .{}) orelse return error.OutOfMemory;
    objc.ivarPtr(*WindowEvents, obj, events_ivar).* = events;
    return obj;
}
