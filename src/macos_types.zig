//! Foundation / CoreGraphics value types, and AppKit enums and flag sets (64-bit macOS).
//!
//! Flag sets are `bitpack struct(u64)` (NSUInteger) so they combine like the Windows package's,
//! e.g. `WindowStyleMask{ .titled = true, .closable = true }`.

pub const CGFloat = f64;
pub const NSInteger = isize;
pub const NSUInteger = usize;

pub const NSPoint = extern struct {
    x: CGFloat = 0,
    y: CGFloat = 0,
};

pub const NSSize = extern struct {
    width: CGFloat = 0,
    height: CGFloat = 0,
};

/// Origin is bottom-left in AppKit coordinates.
pub const NSRect = extern struct {
    origin: NSPoint = .{},
    size: NSSize = .{},

    pub fn init(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) NSRect {
        return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = w, .height = h } };
    }
};

pub const CGPoint = NSPoint;
pub const CGSize = NSSize;
pub const CGRect = NSRect;

/// NSWindowStyleMask.
pub const WindowStyleMask = bitpack struct(u64) {
    titled: bool = false, // 1 << 0
    closable: bool = false, // 1 << 1
    miniaturizable: bool = false, // 1 << 2
    resizable: bool = false, // 1 << 3
    utility_window: bool = false, // 1 << 4
    _r5: u1 = 0,
    doc_modal_window: bool = false, // 1 << 6
    nonactivating_panel: bool = false, // 1 << 7
    _r8: u4 = 0,
    unified_title_and_toolbar: bool = false, // 1 << 12
    hud_window: bool = false, // 1 << 13
    full_screen: bool = false, // 1 << 14
    full_size_content_view: bool = false, // 1 << 15
    _r16: u48 = 0,

    pub const borderless: WindowStyleMask = .{};
    /// Titled, closable, miniaturizable and resizable: a normal app window.
    pub const standard: WindowStyleMask = .{ .titled = true, .closable = true, .miniaturizable = true, .resizable = true };
};

/// NSBackingStoreType. Only `.buffered` is supported by modern macOS.
pub const BackingStoreType = enum(NSUInteger) {
    retained = 0,
    nonretained = 1,
    buffered = 2,
};

/// NSApplicationActivationPolicy.
pub const ActivationPolicy = enum(NSInteger) {
    /// Dock icon and menu bar, like a normal app.
    regular = 0,
    accessory = 1,
    prohibited = 2,
};

/// NSEventType.
pub const EventType = enum(NSUInteger) {
    left_mouse_down = 1,
    left_mouse_up = 2,
    right_mouse_down = 3,
    right_mouse_up = 4,
    mouse_moved = 5,
    left_mouse_dragged = 6,
    right_mouse_dragged = 7,
    mouse_entered = 8,
    mouse_exited = 9,
    key_down = 10,
    key_up = 11,
    flags_changed = 12,
    app_kit_defined = 13,
    system_defined = 14,
    application_defined = 15,
    periodic = 16,
    cursor_update = 17,
    rotate = 18,
    begin_gesture = 19,
    end_gesture = 20,
    scroll_wheel = 22,
    tablet_point = 23,
    tablet_proximity = 24,
    other_mouse_down = 25,
    other_mouse_up = 26,
    other_mouse_dragged = 27,
    gesture = 29,
    magnify = 30,
    swipe = 31,
    smart_magnify = 32,
    quick_look = 33,
    pressure = 34,
    direct_touch = 37,
    change_mode = 38,
    _,
};

/// NSEventMaskAny.
pub const event_mask_any: u64 = ~@as(u64, 0);

/// NSEventModifierFlags (the low 16 bits are device-dependent).
pub const ModifierFlags = bitpack struct(u64) {
    _device: u16 = 0,
    caps_lock: bool = false, // 1 << 16
    shift: bool = false, // 1 << 17
    control: bool = false, // 1 << 18
    option: bool = false, // 1 << 19
    command: bool = false, // 1 << 20
    numeric_pad: bool = false, // 1 << 21
    help: bool = false, // 1 << 22
    function: bool = false, // 1 << 23
    _r24: u40 = 0,
};

/// Hardware-independent virtual key codes (Carbon kVK_*), as returned by `Event.keyCode`.
/// Letter codes follow the ANSI keyboard *position*, not the character.
pub const KeyCode = enum(u16) {
    a = 0x00,
    s = 0x01,
    d = 0x02,
    f = 0x03,
    h = 0x04,
    g = 0x05,
    z = 0x06,
    x = 0x07,
    c = 0x08,
    v = 0x09,
    b = 0x0B,
    q = 0x0C,
    w = 0x0D,
    e = 0x0E,
    r = 0x0F,
    y = 0x10,
    t = 0x11,
    @"1" = 0x12,
    @"2" = 0x13,
    @"3" = 0x14,
    @"4" = 0x15,
    @"6" = 0x16,
    @"5" = 0x17,
    equal = 0x18,
    @"9" = 0x19,
    @"7" = 0x1A,
    minus = 0x1B,
    @"8" = 0x1C,
    @"0" = 0x1D,
    right_bracket = 0x1E,
    o = 0x1F,
    u = 0x20,
    left_bracket = 0x21,
    i = 0x22,
    p = 0x23,
    @"return" = 0x24,
    l = 0x25,
    j = 0x26,
    quote = 0x27,
    k = 0x28,
    semicolon = 0x29,
    backslash = 0x2A,
    comma = 0x2B,
    slash = 0x2C,
    n = 0x2D,
    m = 0x2E,
    period = 0x2F,
    tab = 0x30,
    space = 0x31,
    grave = 0x32,
    delete = 0x33,
    escape = 0x35,
    right_command = 0x36,
    command = 0x37,
    shift = 0x38,
    caps_lock = 0x39,
    option = 0x3A,
    control = 0x3B,
    right_shift = 0x3C,
    right_option = 0x3D,
    right_control = 0x3E,
    function = 0x3F,
    f17 = 0x40,
    f18 = 0x4F,
    f19 = 0x50,
    f20 = 0x5A,
    f5 = 0x60,
    f6 = 0x61,
    f7 = 0x62,
    f3 = 0x63,
    f8 = 0x64,
    f9 = 0x65,
    f11 = 0x67,
    f13 = 0x69,
    f16 = 0x6A,
    f14 = 0x6B,
    f10 = 0x6D,
    f12 = 0x6F,
    f15 = 0x71,
    help = 0x72,
    home = 0x73,
    page_up = 0x74,
    forward_delete = 0x75,
    f4 = 0x76,
    end = 0x77,
    f2 = 0x78,
    page_down = 0x79,
    f1 = 0x7A,
    left_arrow = 0x7B,
    right_arrow = 0x7C,
    down_arrow = 0x7D,
    up_arrow = 0x7E,
    _,
};
