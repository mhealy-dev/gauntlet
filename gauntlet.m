//
//  gauntlet.m — minimal system-wide cursor replacer for macOS
//
//  Registers replacement images for system cursor identifiers via private
//  CoreGraphics/SkyLight APIs. Registrations live in the WindowServer session:
//  they do not survive logout, so worst case is always fixed by logging out.
//
//  Usage:
//    gauntlet use <name>    apply <repo>/gloves/<name> and make it current
//    gauntlet use           re-apply the current glove (used by the LaunchAgent)
//    gauntlet gloves        list installed gloves, marking the current one
//    gauntlet apply <dir>   apply cursors from an arbitrary directory
//    gauntlet reset         restore stock macOS cursors and clear the current glove
//    gauntlet list          list supported cursor names
//
//  Glove directory layout:
//    <slot>.png            1x image for one cursor slot (e.g. 32x32 px)
//    <slot>@2x.png         optional retina image (double pixels)
//    default.png           optional fallback used for every slot without its
//                          own PNG — this is how one pointer covers everything
//    skip                  optional: slot names to leave stock, one per line
//    hotspots.json         optional: {"arrow": {"x": 4, "y": 2}, ...}
//                          hotspot is in 1x pixel coords, default 0,0
//
//  Build:
//    clang -fobjc-arc -fmodules -o gauntlet gauntlet.m \
//      -framework AppKit -framework ApplicationServices
//

@import AppKit;
@import ApplicationServices;
#include <mach-o/dyld.h>

#pragma mark - Private API declarations
//  These CoreGraphics/SkyLight cursor APIs are undocumented; the signatures
//  below were originally reverse-engineered by Joe Ranieri and Alex Zielenski.

typedef int CGSConnectionID;
typedef int CGSCursorID;

CG_EXTERN CGSConnectionID CGSMainConnectionID(void);

/* Registers images for a cursor identifier, optionally globally (all apps). */
CG_EXTERN CGError CGSRegisterCursorWithImages(CGSConnectionID cid,
                                              char *cursorName,
                                              bool setGlobally, bool instantly,
                                              CGSize cursorSize, CGPoint hotspot,
                                              NSUInteger frameCount, CGFloat frameDuration,
                                              CFArrayRef imageArray, int *seed);

/* Reads back the currently registered images for an identifier. */
CG_EXTERN CGError CGSCopyRegisteredCursorImages(CGSConnectionID cid, char *cursorName,
                                                CGSize *imageSize, CGPoint *hotSpot,
                                                NSUInteger *frameCount, CGFloat *frameDuration,
                                                CFArrayRef *imageArray);

/* Core-cursor (com.apple.cursor.N) management. */
CG_EXTERN CGError CoreCursorUnregisterAll(CGSConnectionID cid);
CG_EXTERN CGError CoreCursorSet(CGSConnectionID cid, CGSCursorID cursorID);

#pragma mark - Cursor name table

typedef struct {
    const char *name;        // friendly name used for filenames
    const char *identifier;  // WindowServer identifier
    const char *identifier2; // Tahoe S-variant (macOS 26 renders these), or NULL
} CursorEntry;

// Friendly-name → WindowServer identifier map. S-variants discovered by
// dumping cursor identifier strings from the macOS 26 dyld shared cache.
static const CursorEntry kCursors[] = {
    {"arrow",     "com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowS"}, // main pointer
    {"ibeam",     "com.apple.coregraphics.IBeam", "com.apple.coregraphics.IBeamS"}, // text
    {"ibeamxor", "com.apple.coregraphics.IBeamXOR", NULL}, // inverted text (dark bgs)
    {"wait", "com.apple.coregraphics.Wait", NULL},     // spinner base
    {"ctxarrow", "com.apple.coregraphics.ArrowCtx", NULL}, // contextual-menu arrow
    {"alias", "com.apple.coregraphics.Alias", NULL},
    {"copydefault", "com.apple.coregraphics.Copy", NULL},
    {"move", "com.apple.coregraphics.Move", NULL},
    {"link", "com.apple.cursor.2", NULL},              // link hand
    {"forbidden", "com.apple.cursor.3", NULL},
    {"busy", "com.apple.cursor.4", NULL},                  // loading
    {"counting-down", "com.apple.cursor.15", NULL},        // loading
    {"counting-updown", "com.apple.cursor.16", NULL},      // loading
    {"copydrag", "com.apple.cursor.5", NULL},
    {"crosshair", "com.apple.cursor.7", NULL},
    {"closed", "com.apple.cursor.11", NULL},             // closed hand (drag)
    {"open", "com.apple.cursor.12", NULL},             // open hand
    {"pointing", "com.apple.cursor.13", NULL},             // pointing hand (links/buttons)
    {"resize-we", "com.apple.cursor.19", NULL},
    {"resize-ns", "com.apple.cursor.23", NULL},
    {"zoomin", "com.apple.cursor.42", NULL},
    {NULL, NULL, NULL}
};

// Core cursors are com.apple.cursor.0 ... com.apple.cursor.44, but 44 has no
// stock artwork: nothing restores that slot short of a logout (not even
// CoreCursorUnregisterAll), and stamping a glove image onto it broke the
// window-edge resize pointer on Tahoe. Sweep and reset stop at 43 —
// see CURSORS.md.
static const int kMaxCoreCursor = 43;

// Resize and window-drag cursors: pane splitters (17-19, 21-23) and window
// edges/corners (26-39). Their whole job is showing *which way* something will
// move, so a single static pointer destroys real information — hence the
// "@resize" group that a glove's skip file can name in one line.
static const int kResizeCursors[] = {
    17, 18, 19, 21, 22, 23, 26, 27, 28, 29,
    30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
};
static const int kResizeCursorCount = sizeof(kResizeCursors) / sizeof(kResizeCursors[0]);

#pragma mark - Image loading

// Loads a PNG as a CGImage tagged sRGB (WindowServer expects sRGB data).
static CGImageRef createImageFromPNG(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return NULL;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:data];
    if (!rep) return NULL;
    CGImageRef img = rep.CGImage;
    if (!img) return NULL;

    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef tagged = CGImageCreateCopyWithColorSpace(img, srgb);
    CGColorSpaceRelease(srgb);
    return tagged ?: CGImageRetain(img);
}

#pragma mark - Apply

static BOOL registerCursor(const char *identifier, NSArray *images,
                           CGSize sizeInPoints, CGPoint hotspot) {
    int seed = 0;
    CGError err = CGSRegisterCursorWithImages(CGSMainConnectionID(),
                                              (char *)identifier,
                                              true, true,
                                              sizeInPoints, hotspot,
                                              1, 1.0, // static: 1 frame
                                              (__bridge CFArrayRef)images,
                                              &seed);
    return err == kCGErrorSuccess;
}

// Loads <dir>/<slot>.png plus optional <slot>@2x.png. Returns nil if absent.
static NSArray *loadSlotImages(NSString *dir, NSString *slot) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *png1x = [dir stringByAppendingPathComponent:
                       [slot stringByAppendingString:@".png"]];
    if (![fm fileExistsAtPath:png1x]) return nil;

    CGImageRef img1x = createImageFromPNG(png1x);
    if (!img1x) {
        fprintf(stderr, "gauntlet: could not read %s\n", png1x.UTF8String);
        return nil;
    }
    NSMutableArray *images = [NSMutableArray arrayWithObject:(__bridge id)img1x];
    CGImageRelease(img1x); // array retains

    NSString *png2x = [dir stringByAppendingPathComponent:
                       [slot stringByAppendingString:@"@2x.png"]];
    if ([fm fileExistsAtPath:png2x]) {
        CGImageRef img2x = createImageFromPNG(png2x);
        if (img2x) {
            [images addObject:(__bridge id)img2x];
            CGImageRelease(img2x);
        }
    }
    return images;
}

// Optional <dir>/skip: one slot name per line ("wait", "busy"), a bare core
// cursor ("cursor.15"), or the group "@resize". Listed slots are left stock —
// even when the glove has a default.png that would otherwise cover them.
// '#' starts a comment.
static NSSet *loadSkipList(NSString *dir) {
    NSString *text = [NSString stringWithContentsOfFile:
                      [dir stringByAppendingPathComponent:@"skip"]
                                               encoding:NSUTF8StringEncoding error:nil];
    if (!text) return [NSSet set];

    NSMutableSet *skip = [NSMutableSet set];
    for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:
                               NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:
                          NSCharacterSet.whitespaceCharacterSet];
        NSRange comment = [line rangeOfString:@"#"];
        if (comment.location != NSNotFound) line = [line substringToIndex:comment.location];
        line = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!line.length) continue;

        if ([line isEqualToString:@"@resize"]) {
            for (int i = 0; i < kResizeCursorCount; i++)
                [skip addObject:[NSString stringWithFormat:@"cursor.%d", kResizeCursors[i]]];
        } else if ([line hasPrefix:@"@"]) {
            fprintf(stderr, "gauntlet: unknown skip group '%s' (only @resize)\n",
                    line.UTF8String);
        } else {
            [skip addObject:line];
        }
    }
    return skip;
}

// A named slot can be skipped by its slot name or by its core cursor number,
// so "@resize" also covers named slots like resize-we (com.apple.cursor.19).
static BOOL slotIsSkipped(NSSet *skip, NSString *name, const char *identifier) {
    if ([skip containsObject:name]) return YES;
    NSString *ident = @(identifier);
    if ([ident hasPrefix:@"com.apple."])
        return [skip containsObject:[ident substringFromIndex:10]]; // "cursor.19"
    return NO;
}

static int resetCursors(BOOL announce); // defined below; applying starts clean

static int applyDirectory(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
        fprintf(stderr, "gauntlet: no such directory: %s\n", dir.UTF8String);
        return 1;
    }

    // Start from the stock set so gloves never bleed into each other, and so a
    // slot this glove doesn't cover (or explicitly skips) really is stock.
    resetCursors(NO);

    // Optional hotspots.json: {"arrow": {"x": 4, "y": 2}, ...} in 1x pixels.
    NSDictionary *hotspots = @{};
    NSData *hsData = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"hotspots.json"]];
    if (hsData) {
        NSError *jsonErr = nil;
        hotspots = [NSJSONSerialization JSONObjectWithData:hsData options:0 error:&jsonErr] ?: @{};
        if (jsonErr)
            fprintf(stderr, "gauntlet: ignoring malformed hotspots.json: %s\n",
                    jsonErr.localizedDescription.UTF8String);
    }

    // Optional default.png: covers every slot the glove doesn't name explicitly,
    // including core cursors with no friendly name. This is what makes a
    // one-pointer-for-everything glove possible.
    NSArray *defaultImages = loadSlotImages(dir, @"default");
    CGSize defaultSize = CGSizeZero;
    CGPoint defaultHotspot = CGPointZero;
    if (defaultImages) {
        CGImageRef base = (__bridge CGImageRef)defaultImages[0];
        defaultSize = CGSizeMake(CGImageGetWidth(base), CGImageGetHeight(base));
        NSDictionary *hs = hotspots[@"default"];
        defaultHotspot = CGPointMake([hs[@"x"] doubleValue], [hs[@"y"] doubleValue]);
    }

    NSSet *skip = loadSkipList(dir);
    NSMutableSet *handled = [NSMutableSet set];
    int applied = 0, failed = 0, skipped = 0;

    for (int i = 0; kCursors[i].name; i++) {
        NSString *name = @(kCursors[i].name);

        if (slotIsSkipped(skip, name, kCursors[i].identifier)) {
            // Leave stock, and keep the default.png sweep off it too.
            [handled addObject:@(kCursors[i].identifier)];
            if (kCursors[i].identifier2) [handled addObject:@(kCursors[i].identifier2)];
            skipped++;
            continue;
        }

        NSArray *images = loadSlotImages(dir, name);
        CGSize size;
        CGPoint hotspot;

        if (images) {
            CGImageRef base = (__bridge CGImageRef)images[0];
            size = CGSizeMake(CGImageGetWidth(base), CGImageGetHeight(base));
            NSDictionary *hs = hotspots[name];
            hotspot = CGPointMake([hs[@"x"] doubleValue], [hs[@"y"] doubleValue]);
        } else if (defaultImages) {
            images = defaultImages;
            size = defaultSize;
            hotspot = defaultHotspot;
        } else {
            continue; // no art for this slot; leave it stock
        }

        BOOL ok = registerCursor(kCursors[i].identifier, images, size, hotspot);
        [handled addObject:@(kCursors[i].identifier)];
        // macOS 26 Tahoe renders the S-variant identifiers; register both.
        if (kCursors[i].identifier2) {
            ok = registerCursor(kCursors[i].identifier2, images, size, hotspot) && ok;
            [handled addObject:@(kCursors[i].identifier2)];
        }

        if (ok) {
            printf("applied %-12s -> %s%s%s\n", name.UTF8String, kCursors[i].identifier,
                   kCursors[i].identifier2 ? " + " : "",
                   kCursors[i].identifier2 ?: "");
            applied++;
        } else {
            fprintf(stderr, "gauntlet: FAILED to register %s (%s)\n",
                    name.UTF8String, kCursors[i].identifier);
            failed++;
        }
    }

    // Sweep the rest of the core cursor range with the default image.
    if (defaultImages) {
        int swept = 0;
        for (int n = 0; n <= kMaxCoreCursor; n++) {
            NSString *ident = [NSString stringWithFormat:@"com.apple.cursor.%d", n];
            if ([handled containsObject:ident]) continue;
            if ([skip containsObject:[NSString stringWithFormat:@"cursor.%d", n]]) {
                skipped++;
                continue;
            }
            if (registerCursor(ident.UTF8String, defaultImages, defaultSize, defaultHotspot))
                swept++;
        }
        if (swept) printf("applied default      -> %d further core cursor(s)\n", swept);
        applied += swept;
    }

    if (applied == 0 && failed == 0) {
        fprintf(stderr, "gauntlet: no matching .png files in %s (see `gauntlet list`)\n",
                dir.UTF8String);
        return 1;
    }
    printf("%d cursor(s) applied", applied);
    if (skipped) printf(", %d left stock", skipped);
    if (failed)  printf(", %d failed", failed);
    printf("\n");
    return failed ? 1 : 0;
}

#pragma mark - Reset

// Restore a coregraphics.* cursor from AppKit's pristine NSCursor images.
static void restoreFromNSCursor(const char *identifier, NSCursor *cursor) {
    NSImage *image = cursor.image;
    NSMutableArray *images = [NSMutableArray array];
    for (NSImageRep *rep in image.representations) {
        NSRect proposed = NSMakeRect(0, 0, rep.pixelsWide, rep.pixelsHigh);
        CGImageRef cg = [rep CGImageForProposedRect:&proposed context:nil hints:nil];
        if (cg) [images addObject:(__bridge id)cg];
    }
    if (!images.count) return;
    registerCursor(identifier, images, image.size, cursor.hotSpot);
}

static int resetCursors(BOOL announce) {
    CGSConnectionID cid = CGSMainConnectionID();

    // Re-register stock images over anything we replaced globally
    // (legacy and Tahoe S-variant identifiers).
    restoreFromNSCursor("com.apple.coregraphics.Arrow",  [NSCursor arrowCursor]);
    restoreFromNSCursor("com.apple.coregraphics.ArrowS", [NSCursor arrowCursor]);
    restoreFromNSCursor("com.apple.coregraphics.IBeam",  [NSCursor IBeamCursor]);
    restoreFromNSCursor("com.apple.coregraphics.IBeamS", [NSCursor IBeamCursor]);

    // Drop all com.apple.cursor.N registrations and reload defaults.
    if (CoreCursorUnregisterAll(cid) == kCGErrorSuccess) {
        for (int x = 0; x <= kMaxCoreCursor; x++) CoreCursorSet(cid, x);
        if (announce) printf("cursors restored (a logout fully resets everything)\n");
        return 0;
    }
    fprintf(stderr, "gauntlet: CoreCursorUnregisterAll failed — log out and back in to reset\n");
    return 1;
}

#pragma mark - Glove management

// The gloves/ directory lives beside the real (symlink-resolved) executable.
static NSString *glovesDirectory(void) {
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    char *buf = malloc(size);
    _NSGetExecutablePath(buf, &size);
    NSString *exe = [@(buf) stringByResolvingSymlinksInPath];
    free(buf);
    return [exe.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"gloves"];
}

static NSString *currentLinkPath(void) {
    return [glovesDirectory() stringByAppendingPathComponent:@".current"];
}

// Name of the currently selected glove, or nil.
static NSString *currentGloveName(void) {
    NSString *target = [[NSFileManager defaultManager]
                        destinationOfSymbolicLinkAtPath:currentLinkPath() error:nil];
    return target.lastPathComponent;
}

static int useGlove(NSString *name) {
    NSFileManager *fm = [NSFileManager defaultManager];

    if (!name) { // re-apply current (login agent path); no glove selected is fine
        name = currentGloveName();
        if (!name) {
            printf("no glove selected\n");
            return 0;
        }
    }

    NSString *dir = [glovesDirectory() stringByAppendingPathComponent:name];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
        fprintf(stderr, "gauntlet: no glove named '%s' in %s (see `gauntlet gloves`)\n",
                name.UTF8String, glovesDirectory().UTF8String);
        return 1;
    }

    int result = applyDirectory(dir);
    if (result == 0) {
        [fm removeItemAtPath:currentLinkPath() error:nil];
        [fm createSymbolicLinkAtPath:currentLinkPath() withDestinationPath:name error:nil];
    }
    return result;
}

static int listGloves(void) {
    NSString *gloves = glovesDirectory();
    NSString *current = currentGloveName();
    NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:gloves error:nil];
    int shown = 0;
    for (NSString *entry in [entries sortedArrayUsingSelector:@selector(compare:)]) {
        if ([entry hasPrefix:@"."]) continue;
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:[gloves stringByAppendingPathComponent:entry]
                                             isDirectory:&isDir];
        if (!isDir) continue;
        printf("%s %s\n", [entry isEqualToString:current] ? "*" : " ", entry.UTF8String);
        shown++;
    }
    if (!shown) printf("no gloves installed in %s\n", gloves.UTF8String);
    return 0;
}

#pragma mark - main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *cmd = argc > 1 ? @(argv[1]) : @"";

        if ([cmd isEqualToString:@"use"]) {
            return useGlove(argc > 2 ? @(argv[2]) : nil);
        }
        if ([cmd isEqualToString:@"gloves"]) {
            return listGloves();
        }
        if ([cmd isEqualToString:@"apply"] && argc > 2) {
            return applyDirectory([@(argv[2]) stringByStandardizingPath]);
        }
        if ([cmd isEqualToString:@"reset"]) {
            [[NSFileManager defaultManager] removeItemAtPath:currentLinkPath() error:nil];
            return resetCursors(YES);
        }
        if ([cmd isEqualToString:@"list"]) {
            for (int i = 0; kCursors[i].name; i++)
                printf("%-12s %s\n", kCursors[i].name, kCursors[i].identifier);
            return 0;
        }

        fprintf(stderr,
                "gauntlet — system-wide cursor replacer\n"
                "usage:\n"
                "  gauntlet use <name>    apply gloves/<name> and make it current\n"
                "  gauntlet use           re-apply the current glove\n"
                "  gauntlet gloves        list installed gloves (* = current)\n"
                "  gauntlet apply <dir>   apply <name>.png (+ optional <name>@2x.png,\n"
                "                         hotspots.json) from any directory\n"
                "  gauntlet reset         restore stock cursors, clear current glove\n"
                "  gauntlet list          list supported cursor names\n");
        return argc <= 1 ? 0 : 1;
    }
}
