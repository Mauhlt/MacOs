# Third-party material

All code in this repository is under the MIT licence in [LICENSE](LICENSE). No
third-party source files are vendored or ported.

The bindings are written by hand to match the Objective-C runtime, Foundation,
AppKit, CoreGraphics and QuartzCore APIs as documented by Apple (class and selector
names, structure layouts and enum and flag values). No SDK header text is copied;
only the interface facts needed to call the system frameworks.

## Run-time libraries (not distributed)

libobjc, AppKit, Foundation and QuartzCore are macOS system libraries opened with
dlopen at run time. They are not linked or shipped with this package.
