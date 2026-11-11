//! Objective-C runtime (libobjc), loaded with dlopen.
//!
//!     try OBJC.load();
//!     const s = OBJC.msgSend(?*OBJC.Object, OBJC.getClass("NSString"), OBJC.sel("stringWithUTF8String:"), .{"hi"});
//!
//! `msgSend` builds the exact C function type from `Ret` and the argument tuple, and uses
//! `objc_msgSend_stret` for large struct returns on x86_64 (Intel Macs) as the ABI requires.
const std = @import("std");
const builtin = @import("builtin");
const dl = @import("dl.zig");

/// `id`: any Objective-C object. Typed wrappers (`APPKIT.Window`, ...) cast to and from this.
pub const Object = opaque {};
pub const Class = opaque {};
/// `SEL`.
pub const Selector = opaque {};
pub const Ivar = opaque {};
/// `IMP`: a method implementation, cast from a `callconv(.c)` Zig function.
pub const Imp = *const fn () callconv(.c) void;

/// Objective-C `BOOL` (signed char on x86_64, bool on arm64; both one byte, 0 / 1).
pub const BOOL = i8;
pub const YES: BOOL = 1;
pub const NO: BOOL = 0;

pub fn toBOOL(b: bool) BOOL {
    return @intFromBool(b);
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

/// libobjc symbols. Field names are the C symbol names.
pub const Symbols = struct {
    objc_getClass: ?*const fn ([*:0]const u8) callconv(.c) ?*Class,
    objc_allocateClassPair: ?*const fn (?*Class, [*:0]const u8, usize) callconv(.c) ?*Class,
    objc_registerClassPair: ?*const fn (*Class) callconv(.c) void,
    objc_msgSend: ?*const fn () callconv(.c) void,
    objc_msgSend_stret: ?*const fn () callconv(.c) void,
    objc_autoreleasePoolPush: ?*const fn () callconv(.c) ?*anyopaque,
    objc_autoreleasePoolPop: ?*const fn (?*anyopaque) callconv(.c) void,
    sel_registerName: ?*const fn ([*:0]const u8) callconv(.c) ?*Selector,
    sel_getName: ?*const fn (*Selector) callconv(.c) [*:0]const u8,
    class_addMethod: ?*const fn (*Class, *Selector, Imp, [*:0]const u8) callconv(.c) BOOL,
    class_addIvar: ?*const fn (*Class, [*:0]const u8, usize, u8, [*:0]const u8) callconv(.c) BOOL,
    class_getInstanceVariable: ?*const fn (*Class, [*:0]const u8) callconv(.c) ?*Ivar,
    class_getName: ?*const fn (?*Class) callconv(.c) [*:0]const u8,
    class_respondsToSelector: ?*const fn (?*Class, *Selector) callconv(.c) BOOL,
    ivar_getOffset: ?*const fn (*Ivar) callconv(.c) isize,
    object_getClass: ?*const fn (?*Object) callconv(.c) ?*Class,
};

/// objc_msgSend_stret only exists on x86_64.
const optional_symbols = [_][]const u8{"objc_msgSend_stret"};

const Loaded = struct {
    syms: Symbols,
    foundation: dl.Library,
    appkit: dl.Library,
    quartz_core: dl.Library,
};
var loaded: ?Loaded = null;

/// Opens libobjc, Foundation, AppKit and QuartzCore (registering their classes).
/// Safe to call more than once. Call from the main thread before using AppKit.
pub fn load() error{ LibraryNotFound, MissingSymbol }!void {
    if (loaded != null) return;
    const objc = try dl.Library.open(&.{"/usr/lib/libobjc.A.dylib"});
    const syms = objc.loadAll(Symbols);
    if (dl.firstMissing(syms, &optional_symbols)) |name| {
        std.log.scoped(.objc).err("libobjc is missing {s}", .{name});
        return error.MissingSymbol;
    }
    loaded = .{
        .syms = syms,
        .foundation = try dl.Library.open(&.{"/System/Library/Frameworks/Foundation.framework/Foundation"}),
        .appkit = try dl.Library.open(&.{"/System/Library/Frameworks/AppKit.framework/AppKit"}),
        .quartz_core = try dl.Library.open(&.{"/System/Library/Frameworks/QuartzCore.framework/QuartzCore"}),
    };
}

pub fn isLoaded() bool {
    return loaded != null;
}

pub fn api() *const Symbols {
    return &(loaded orelse @panic("OBJC: call OBJC.load() first")).syms;
}

/// Looks up a data symbol (e.g. "NSDefaultRunLoopMode") in Foundation / AppKit / QuartzCore.
pub fn frameworkSymbol(comptime T: type, name: [*:0]const u8) ?*const T {
    const l = loaded orelse return null;
    inline for (.{ l.foundation, l.appkit, l.quartz_core }) |lib| {
        if (lib.lookup(*const T, name)) |p| return p;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Classes and selectors (cached per name)
// ---------------------------------------------------------------------------

/// Registered selector for `name`, cached after the first call.
pub fn sel(comptime name: [:0]const u8) *Selector {
    const Cache = struct {
        var value: std.atomic.Value(usize) = .init(0);
    };
    var v = Cache.value.load(.acquire);
    if (v == 0) {
        v = @intFromPtr(api().sel_registerName.?(name.ptr) orelse @panic("sel_registerName failed: " ++ name));
        Cache.value.store(v, .release);
    }
    return @ptrFromInt(v);
}

/// Class named `name`, or null if no loaded framework defines it (e.g. a newer-macOS class).
pub fn lookUpClass(comptime name: [:0]const u8) ?*Class {
    const Cache = struct {
        /// 0 = not looked up, 1 = missing.
        var value: std.atomic.Value(usize) = .init(0);
    };
    var v = Cache.value.load(.acquire);
    if (v == 0) {
        v = if (api().objc_getClass.?(name.ptr)) |cls| @intFromPtr(cls) else 1;
        Cache.value.store(v, .release);
    }
    return if (v == 1) null else @ptrFromInt(v);
}

/// Uncached lookup, for classes registered at runtime (see `ClassBuilder`).
pub fn lookUpClassUncached(name: [*:0]const u8) ?*Class {
    return api().objc_getClass.?(name);
}

/// Like `lookUpClass`, for classes every supported macOS has.
pub fn getClass(comptime name: [:0]const u8) *Class {
    return lookUpClass(name) orelse @panic("Objective-C class not found: " ++ name);
}

/// True if instances of `obj`'s class respond to `selector` (feature-detect newer methods).
pub fn respondsTo(obj: anytype, selector: *Selector) bool {
    return api().class_respondsToSelector.?(api().object_getClass.?(asObject(obj)), selector) != 0;
}

// ---------------------------------------------------------------------------
// Message sending
// ---------------------------------------------------------------------------

fn asObject(target: anytype) ?*Object {
    return @ptrCast(target);
}

/// The exact C type of objc_msgSend for this return type and argument tuple.
pub fn MsgSendFn(comptime Ret: type, comptime Args: type) type {
    const A = @typeInfo(Args).@"struct".field_types;
    const S = *Selector;
    const O = ?*Object;
    return switch (A.len) {
        0 => fn (O, S) callconv(.c) Ret,
        1 => fn (O, S, A[0]) callconv(.c) Ret,
        2 => fn (O, S, A[0], A[1]) callconv(.c) Ret,
        3 => fn (O, S, A[0], A[1], A[2]) callconv(.c) Ret,
        4 => fn (O, S, A[0], A[1], A[2], A[3]) callconv(.c) Ret,
        5 => fn (O, S, A[0], A[1], A[2], A[3], A[4]) callconv(.c) Ret,
        6 => fn (O, S, A[0], A[1], A[2], A[3], A[4], A[5]) callconv(.c) Ret,
        7 => fn (O, S, A[0], A[1], A[2], A[3], A[4], A[5], A[6]) callconv(.c) Ret,
        8 => fn (O, S, A[0], A[1], A[2], A[3], A[4], A[5], A[6], A[7]) callconv(.c) Ret,
        else => @compileError("msgSend supports up to 8 arguments"),
    };
}

/// True when `Ret` must be returned through objc_msgSend_stret (x86_64 structs > 16 bytes).
pub fn usesStret(comptime arch: std.Target.Cpu.Arch, comptime Ret: type) bool {
    return arch == .x86_64 and @typeInfo(Ret) == .@"struct" and @sizeOf(Ret) > 16;
}

/// `[target selector args...]`. `target` is any object or class pointer (or null).
/// Argument types must be concrete (write `@as(f64, 1)`, not `1`).
pub fn msgSend(comptime Ret: type, target: anytype, selector: *Selector, args: anytype) Ret {
    const F = MsgSendFn(Ret, @TypeOf(args));
    const raw = if (comptime usesStret(builtin.cpu.arch, Ret)) api().objc_msgSend_stret.? else api().objc_msgSend.?;
    const f: *const F = @ptrCast(raw);
    return @call(.auto, f, .{ asObject(target), selector } ++ args);
}

// ---------------------------------------------------------------------------
// Memory management (manual retain/release; no ARC in Zig)
// ---------------------------------------------------------------------------

pub fn retain(obj: anytype) @TypeOf(obj) {
    return @ptrCast(msgSend(?*Object, obj, sel("retain"), .{}));
}
pub fn release(obj: anytype) void {
    msgSend(void, obj, sel("release"), .{});
}
pub fn autorelease(obj: anytype) @TypeOf(obj) {
    return @ptrCast(msgSend(?*Object, obj, sel("autorelease"), .{}));
}

/// Wrap each frame / event-loop iteration in one so autoreleased objects are freed.
pub const AutoreleasePool = struct {
    token: ?*anyopaque,

    pub fn push() AutoreleasePool {
        return .{ .token = api().objc_autoreleasePoolPush.?() };
    }
    pub fn pop(self: AutoreleasePool) void {
        api().objc_autoreleasePoolPop.?(self.token);
    }
};

// ---------------------------------------------------------------------------
// Defining classes at runtime (delegates, custom views)
// ---------------------------------------------------------------------------

pub const ClassBuilder = struct {
    class: *Class,

    /// Starts a subclass of `superclass`. Null if a class named `name` already exists.
    pub fn begin(superclass: *Class, name: [*:0]const u8) ?ClassBuilder {
        const cls = api().objc_allocateClassPair.?(superclass, name, 0) orelse return null;
        return .{ .class = cls };
    }
    /// `imp` is a `callconv(.c)` function taking (self: *Object, _cmd: *Selector, args...).
    /// `types` is the Objective-C type encoding, e.g. "v@:@" (void, self, _cmd, id).
    pub fn addMethod(self: ClassBuilder, comptime name: [:0]const u8, imp: anytype, types: [*:0]const u8) bool {
        return api().class_addMethod.?(self.class, sel(name), @ptrCast(imp), types) != 0;
    }
    /// Adds an instance variable holding one `T` (e.g. a `?*anyopaque` back-pointer).
    pub fn addIvar(self: ClassBuilder, name: [*:0]const u8, comptime T: type, types: [*:0]const u8) bool {
        return api().class_addIvar.?(self.class, name, @sizeOf(T), std.math.log2_int(usize, @alignOf(T)), types) != 0;
    }
    pub fn register(self: ClassBuilder) *Class {
        api().objc_registerClassPair.?(self.class);
        return self.class;
    }
};

/// Pointer to instance variable `name` (of type `T`) inside `obj`.
pub fn ivarPtr(comptime T: type, obj: anytype, name: [*:0]const u8) *T {
    const o = asObject(obj).?;
    const ivar = api().class_getInstanceVariable.?(api().object_getClass.?(o).?, name) orelse @panic("no such ivar");
    const offset: usize = @intCast(api().ivar_getOffset.?(ivar));
    return @ptrFromInt(@intFromPtr(o) + offset);
}
