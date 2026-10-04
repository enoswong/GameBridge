// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental, process-local Wine/DXMT alpha bridge. No runtime files are patched.
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <crt_externs.h>
#include <stdio.h>
#include <string.h>
#import <CommonCrypto/CommonDigest.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>

static void (*originalPresent)(id,SEL,id);
static void (*originalPresentDuration)(id,SEL,id,CFTimeInterval);
static unsigned presentCount;
static void traceAlpha(id<MTLCommandBuffer> buffer, id<CAMetalDrawable> drawable) {
    if (!getenv("GAMEBRIDGE_ALPHA_TRACE")) return;
    unsigned frame = __atomic_fetch_add(&presentCount,1,__ATOMIC_RELAXED);
    if (frame % 120 || frame > 600) return;
    id<MTLTexture> t=drawable.texture;
    BOOL half = t.pixelFormat==MTLPixelFormatRGBA16Float;
    NSUInteger bpp=half?8:4;
    if (!half && t.pixelFormat!=MTLPixelFormatBGRA8Unorm && t.pixelFormat!=MTLPixelFormatBGRA8Unorm_sRGB && t.pixelFormat!=MTLPixelFormatRGBA8Unorm && t.pixelFormat!=MTLPixelFormatRGBA8Unorm_sRGB) {
        fprintf(stderr,"[GameBridge alpha] diagnostic unsupported format=%lu\n",(unsigned long)t.pixelFormat);return;
    }
    NSUInteger stride=(t.width*bpp+255)&~255;
    NSUInteger width=t.width,height=t.height;
    id<MTLBuffer> data=[buffer.device newBufferWithLength:stride*height options:MTLResourceStorageModeShared];
    id<MTLBlitCommandEncoder> blit=[buffer blitCommandEncoder];
    [blit copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width,height,1) toBuffer:data destinationOffset:0 destinationBytesPerRow:stride destinationBytesPerImage:stride*height];
    [blit endEncoding];
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> done) {
        if(done.status!=MTLCommandBufferStatusCompleted)return;
        NSUInteger zero=0,one=0;
        for(NSUInteger y=0;y<height;y++)for(NSUInteger x=0;x<width;x++) {
            unsigned char *p=(unsigned char*)data.contents+y*stride+x*bpp;
            unsigned a=half?*(unsigned short*)(p+6):p[3];
            zero+=(a==0);one+=(a==(half?0x3c00:255));
        }
        fprintf(stderr,"[GameBridge alpha] frame=%u alpha-zero=%lu alpha-one=%lu pixels=%lu\n",frame,(unsigned long)zero,(unsigned long)one,(unsigned long)(width*height));
    }];
}
static void tracedPresent(id self,SEL cmd,id drawable) { traceAlpha(self,drawable);originalPresent(self,cmd,drawable); }
static void tracedDuration(id self,SEL cmd,id drawable,CFTimeInterval duration) { traceAlpha(self,drawable);originalPresentDuration(self,cmd,drawable,duration); }
static void installAlphaTrace(CAMetalLayer *layer) {
    if (!getenv("GAMEBRIDGE_ALPHA_TRACE")||!layer.device)return;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        id<MTLCommandQueue> queue=[layer.device newCommandQueue];
        id<MTLCommandBuffer> buffer=[queue commandBuffer];
        Class cls=object_getClass(buffer);
        SEL a=@selector(presentDrawable:),b=@selector(presentDrawable:afterMinimumDuration:);
        Method ma=class_getInstanceMethod(cls,a),mb=class_getInstanceMethod(cls,b);
        if(ma && mb) {
            originalPresent=(void*)method_getImplementation(ma);
            originalPresentDuration=(void*)method_getImplementation(mb);
            class_replaceMethod(cls,a,(IMP)tracedPresent,method_getTypeEncoding(ma));
            class_replaceMethod(cls,b,(IMP)tracedDuration,method_getTypeEncoding(mb));
            fprintf(stderr,"[GameBridge alpha] GPU alpha diagnostic installed\n");
        }
    });
}

static char alphaBackingKey;
static char alphaWindowKey;
static void (*originalUpdateLayer)(id, SEL);
static void (*originalUseAlpha)(id, SEL, BOOL);
static void clearBacking(NSView *view) {
    view.layer.contents = nil;
    view.layer.backgroundColor = CGColorGetConstantColor(kCGColorClear);
    view.layer.opaque = NO;
}
static void updateAlphaBacking(id self, SEL cmd) {
    originalUpdateLayer(self, cmd);
    if (objc_getAssociatedObject(self, &alphaBackingKey)) clearBacking(self);
}
static void maintainWindowAlpha(id self, SEL cmd, BOOL value) {
    originalUseAlpha(self, cmd, objc_getAssociatedObject(self, &alphaWindowKey) ? YES : value);
}
static void configureBacking(NSView *metalView) {
    Class content = NSClassFromString(@"WineContentView");
    if (content && !originalUpdateLayer) {
        Method m = class_getInstanceMethod(content, @selector(updateLayer));
        if (m) {
            originalUpdateLayer = (void *)method_getImplementation(m);
            class_replaceMethod(content, @selector(updateLayer), (IMP)updateAlphaBacking, method_getTypeEncoding(m));
        }
    }
    for (NSView *view = metalView.superview; view; view = view.superview) {
        if (content && [view isKindOfClass:content]) {
            objc_setAssociatedObject(view, &alphaBackingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            clearBacking(view);
        }
    }
    NSWindow *window = metalView.window;
    SEL setter = NSSelectorFromString(@"setUsePerPixelAlpha:");
    if ([window respondsToSelector:setter]) {
        if (!originalUseAlpha) {
            Class cls = object_getClass(window);
            Method m = class_getInstanceMethod(cls, setter);
            originalUseAlpha = (void *)method_getImplementation(m);
            class_replaceMethod(cls, setter, (IMP)maintainWindowAlpha, method_getTypeEncoding(m));
        }
        objc_setAssociatedObject(window, &alphaWindowKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static void (*originalSetOpaque)(id, SEL, BOOL);
static BOOL transparentView(id self, SEL cmd) { return NO; }

static BOOL isDeskrawl(void) {
    char **argv = *_NSGetArgv();
    for (int i = 0; i < *_NSGetArgc(); i++) {
        const char *base = strrchr(argv[i], '/');
        base = base ? base + 1 : argv[i];
        const char *windowsBase = strrchr(base, '\\');
        if (windowsBase) base = windowsBase + 1;
        if (!strcasecmp(base, "Deskrawl.exe")) return YES;
    }
    return NO;
}

static void alphaSetOpaque(CAMetalLayer *layer, SEL cmd, BOOL requested) {
    // WineMetalView is the owner of DXMT's presentation layer. Leave unrelated
    // layers alone, including any framework-internal Metal layers.
    id delegate = layer.delegate;
    Class wineView = NSClassFromString(@"WineMetalView");
    if (!wineView || ![delegate isKindOfClass:wineView]) {
        originalSetOpaque(layer, cmd, requested);
        return;
    }
    installAlphaTrace(layer);
    originalSetOpaque(layer, cmd, NO);
    layer.backgroundColor = CGColorGetConstantColor(kCGColorClear);
    // DXMT updates layer properties on the main thread. Defer rather than
    // synchronously wait if a different caller reaches this hook off-main.
    void (^configure)(void) = ^{
        configureBacking((NSView *)delegate);
        class_replaceMethod(wineView, @selector(isOpaque), (IMP)transparentView, "c@:");
        NSWindow *window = [(NSView *)delegate window];
        SEL alpha = NSSelectorFromString(@"setUsePerPixelAlpha:");
        SEL check = NSSelectorFromString(@"checkTransparency");
        if ([window respondsToSelector:alpha] && [window respondsToSelector:check]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(window, alpha, YES);
            ((void (*)(id, SEL))objc_msgSend)(window, check);
            [window setBackgroundColor:NSColor.clearColor];
            [window setOpaque:NO];
            static BOOL logged = NO;
            if (!logged) {
                fprintf(stderr, "[GameBridge alpha] Wine window and Metal layer use per-pixel alpha\n");
                logged = YES;
            }
        }
    };
    if (NSThread.isMainThread) configure();
    else dispatch_async(dispatch_get_main_queue(), configure);
}

// Ownership is separate from the current bundle hash so a later version can
// replace a DLL previously installed by GameBridge. A user replacement invalidates
// ownership immediately. Sidecars never authorize replacing a symlink or directory.
static NSString *pointerFileDigest(NSString *path) {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (![attributes[NSFileType] isEqual:NSFileTypeRegular] ||
        [attributes[NSFileSize] unsignedLongLongValue] > 4*1024*1024) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *result = [NSMutableString string];
    for (unsigned i=0; i<sizeof(hash); i++) [result appendFormat:@"%02x", hash[i]];
    return result;
}
static void installOwnedPointer(NSData *data, NSString *target, NSString *digest) {
    NSString *ownership = [target stringByAppendingString:@".gamebridge-sha256"];
    NSString *lockPath = [target stringByAppendingString:@".gamebridge-lock"];
    int lock = open(lockPath.fileSystemRepresentation, O_CREAT|O_RDWR|O_NOFOLLOW, 0600);
    if (lock < 0) return;
    if (flock(lock, LOCK_EX) != 0) { close(lock); return; }
    @try {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSDictionary *record = [fm attributesOfItemAtPath:ownership error:nil];
        NSString *previous = nil;
        if (record) {
            if (![record[NSFileType] isEqual:NSFileTypeRegular] ||
                [record[NSFileSize] unsignedLongLongValue] > 65) return;
            previous = [[NSString stringWithContentsOfFile:ownership encoding:NSASCIIStringEncoding error:nil]
                        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
            if (previous.length != 64 || [previous rangeOfCharacterFromSet:nonHex].location != NSNotFound) return;
        }
        NSDictionary *installed = [fm attributesOfItemAtPath:target error:nil];
        NSString *current = installed ? pointerFileDigest(target) : nil;
        if (installed && ![current isEqualToString:digest] &&
            (!previous || ![current isEqualToString:previous])) {
            fprintf(stderr,"[GameBridge] Preserved unrecognized Deskrawl version.dll\n");
            return;
        }
        if (![current isEqualToString:digest]) {
            NSString *temporary = [target stringByAppendingFormat:@".%@.tmp",NSUUID.UUID.UUIDString];
            if (![data writeToFile:temporary options:NSDataWritingWithoutOverwriting error:nil]) return;
            // Fresh installs use an exclusive hard link; upgrades atomically replace
            // only the regular file whose digest matched our ownership record.
            int status = installed ? rename(temporary.fileSystemRepresentation, target.fileSystemRepresentation)
                                   : link(temporary.fileSystemRepresentation, target.fileSystemRepresentation);
            unlink(temporary.fileSystemRepresentation);
            if (status != 0) return;
            fprintf(stderr,"[GameBridge] %s Deskrawl input compatibility before launch\n", installed ? "Updated" : "Installed");
        }
        // Also repairs an interrupted sidecar write when the target already equals
        // the currently verified bundle. Write after the DLL is installed.
        [[digest stringByAppendingString:@"\n"] writeToFile:ownership atomically:YES encoding:NSASCIIStringEncoding error:nil];
    } @finally {
        flock(lock, LOCK_UN);
        close(lock);
    }
}

// Install before Wine resolves UnityPlayer's imports, including games downloaded
// during this Steam session. Never overwrite an unrecognized game-local DLL.
static void provisionPointer(void) {
    const char *source = getenv("GAMEBRIDGE_DESKRAWL_POINTER");
    const char *digest = getenv("GAMEBRIDGE_DESKRAWL_POINTER_SHA256");
    const char *prefix = getenv("WINEPREFIX");
    if (!source || !digest || !prefix) return;
    @autoreleasepool {
        NSString *root = [[NSString stringWithUTF8String:prefix] stringByResolvingSymlinksInPath];
        NSString *executable = nil;
        char **argv = *_NSGetArgv();
        for (int i=0; i<*_NSGetArgc(); i++) {
            NSString *arg = [[NSString stringWithUTF8String:argv[i]] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
            if ([arg.lastPathComponent caseInsensitiveCompare:@"Deskrawl.exe"] != NSOrderedSame) continue;
            if ([arg.lowercaseString hasPrefix:@"c:/"]) executable = [[root stringByAppendingPathComponent:@"drive_c"] stringByAppendingPathComponent:[arg substringFromIndex:3]];
            else if ([arg hasPrefix:@"/"]) executable = arg;
        }
        executable = executable.stringByStandardizingPath;
        if (!executable || ![executable hasPrefix:[root stringByAppendingString:@"/"]] ||
            ![executable.stringByResolvingSymlinksInPath isEqualToString:executable]) return;
        NSFileManager *fm = NSFileManager.defaultManager;
        NSDictionary *attributes = [fm attributesOfItemAtPath:[NSString stringWithUTF8String:source] error:nil];
        if (![attributes[NSFileType] isEqual:NSFileTypeRegular] || [attributes[NSFileSize] unsignedLongLongValue] > 4*1024*1024) return;
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:source]];
        if (!data.length) return;
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
        NSMutableString *actual = [NSMutableString string];
        for (unsigned i=0;i<sizeof(hash);i++) [actual appendFormat:@"%02x",hash[i]];
        if (![actual isEqualToString:[NSString stringWithUTF8String:digest]]) {
            fprintf(stderr,"[GameBridge] Pointer component hash mismatch; installation refused\n"); return;
        }
        NSString *target = [executable.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"version.dll"];
        installOwnedPointer(data, target, actual);
    }
}

__attribute__((constructor)) static void install(void) {
    const char *enabled = getenv("GAMEBRIDGE_DESKRAWL_ALPHA");
    if (!enabled || strcmp(enabled, "1") || !isDeskrawl()) return;
    provisionPointer();
    Class cls = CAMetalLayer.class;
    SEL sel = @selector(setOpaque:);
    Method method = class_getInstanceMethod(cls, sel);
    originalSetOpaque = (void *)method_getImplementation(method);
    // Do not replace CALayer's inherited implementation for all layer classes.
    if (!class_addMethod(cls, sel, (IMP)alphaSetOpaque, method_getTypeEncoding(method)))
        class_replaceMethod(cls, sel, (IMP)alphaSetOpaque, method_getTypeEncoding(method));
    fprintf(stderr, "[GameBridge alpha] Deskrawl-only bridge enabled\n");
}
