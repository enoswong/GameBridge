// SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
@interface WineContentView : NSView
@end
@implementation WineContentView
- (void)updateLayer { self.layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack); self.layer.opaque = YES; }
@end
@interface WineMetalView : NSView <CALayerDelegate>
- (NSWindow *)window;
- (BOOL)isOpaque;
@end
@implementation WineMetalView
- (NSWindow *)window { return nil; }
- (BOOL)isOpaque { return YES; }
@end
int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL expectAlpha = argc > 1 && !strcmp(argv[1], "alpha");
        WineMetalView *view = [WineMetalView new];
        WineContentView *backing = [WineContentView new];
        backing.wantsLayer = YES;
        [backing addSubview:view];
        [backing updateLayer];
        CAMetalLayer *wine = [CAMetalLayer layer];
        wine.delegate = view;
        wine.opaque = YES;
        CAMetalLayer *other = [CAMetalLayer layer];
        other.opaque = YES;
        CALayer *plain = [CALayer layer];
        plain.opaque = YES;
        [backing updateLayer];
        BOOL pass = (backing.layer.opaque == !expectAlpha) && (wine.opaque == !expectAlpha) && (view.isOpaque == !expectAlpha)
            && other.opaque && plain.opaque;
        if (expectAlpha) pass = pass && wine.backgroundColor && CGColorGetAlpha(wine.backgroundColor) == 0;
        fprintf(stderr, "alpha=%d wine=%d view=%d unrelated=%d base=%d result=%s\n",
            expectAlpha, wine.opaque, view.isOpaque, other.opaque, plain.opaque, pass ? "PASS" : "FAIL");
        return pass ? 0 : 1;
    }
}
