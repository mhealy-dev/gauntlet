//
//  gauntlet.m — minimal system-wide cursor replacer for macOS
//
//  A ~300-line distillation of Mousecape's mousecloak (alexzielenski/Mousecape).
//  Registers replacement images for system cursor identifiers via private
//  CoreGraphics/SkyLight APIs. Registrations live in the WindowServer session:
//  they do not survive logout, so worst case is always fixed by logging out.
//
//  Usage:
//    gauntlet use <name>    apply cape <repo>/capes/<name> and make it current
//    gauntlet use           re-apply the current cape (used by the LaunchAgent)
//    gauntlet capes         list installed capes, marking the current one
//    gauntlet apply <dir>   apply cursors from an arbitrary directory
//    gauntlet reset         restore stock macOS cursors and clear the current cape
//    gauntlet list          list supported cursor names
//
//  Cursor directory layout:
//    <name>.png            required, 1x image (e.g. 32x32 px)
//    <name>@2x.png         optional retina image (double pixels)
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

#pragma mark - Private API declarations (from Mousecape's CGSInternal headers)

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

// Friendly-name → identifier map (identifiers from Mousecape's MCDefs.m;
// S-variants discovered in the macOS 26 dyld shared cache).
static const CursorEntry kCursors[] = {
    {"arrow",     "com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowS"}, // main pointer
    {"ibeam",     "com.apple.coregraphics.IBeam", "com.apple.coregraphics.IBeamS"}, // text
    {"wait", "com.apple.coregraphics.Wait", NULL},     // spinner base
    {"ctxarrow", "com.apple.coregraphics.ArrowCtx", NULL}, // contextual-menu arrow
    {"alias", "com.apple.coregraphics.Alias", NULL},
    {"copydefault", "com.apple.coregraphics.Copy", NULL},
    {"move", "com.apple.coregraphics.Move", NULL},
    {"link", "com.apple.cursor.2", NULL},              // link hand
    {"forbidden", "com.apple.cursor.3", NULL},
    {"busy", "com.apple.cursor.4", NULL},
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

static const char *identifierForName(NSString *name) {
    for (int i = 0; kCursors[i].name; i++)
        if ([name isEqualToString:@(kCursors[i].name)])
            return kCursors[i].identifier;
    return NULL;
}

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

static int applyDirectory(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
        fprintf(stderr, "gauntlet: no such directory: %s\n", dir.UTF8String);
        return 1;
    }

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

    int applied = 0, failed = 0;
    for (int i = 0; kCursors[i].name; i++) {
        NSString *name = @(kCursors[i].name);
        NSString *png1x = [dir stringByAppendingPathComponent:
                           [name stringByAppendingString:@".png"]];
        if (![fm fileExistsAtPath:png1x]) continue;

        CGImageRef img1x = createImageFromPNG(png1x);
        if (!img1x) {
            fprintf(stderr, "gauntlet: could not read %s\n", png1x.UTF8String);
            failed++;
            continue;
        }

        NSMutableArray *images = [NSMutableArray arrayWithObject:(__bridge id)img1x];
        CGImageRelease(img1x); // array retains

        NSString *png2x = [dir stringByAppendingPathComponent:
                           [name stringByAppendingString:@"@2x.png"]];
        if ([fm fileExistsAtPath:png2x]) {
            CGImageRef img2x = createImageFromPNG(png2x);
            if (img2x) {
                [images addObject:(__bridge id)img2x];
                CGImageRelease(img2x);
            }
        }

        // Size in points == 1x pixel size.
        CGImageRef base = (__bridge CGImageRef)images[0];
        CGSize size = CGSizeMake(CGImageGetWidth(base), CGImageGetHeight(base));

        NSDictionary *hs = hotspots[name];
        CGPoint hotspot = CGPointMake([hs[@"x"] doubleValue], [hs[@"y"] doubleValue]);

        BOOL ok = registerCursor(kCursors[i].identifier, images, size, hotspot);
        // macOS 26 Tahoe renders the S-variant identifiers; register both.
        if (kCursors[i].identifier2)
            ok = registerCursor(kCursors[i].identifier2, images, size, hotspot) && ok;

        if (ok) {
            printf("applied %-10s -> %s%s%s\n", name.UTF8String, kCursors[i].identifier,
                   kCursors[i].identifier2 ? " + " : "",
                   kCursors[i].identifier2 ?: "");
            applied++;
        } else {
            fprintf(stderr, "gauntlet: FAILED to register %s (%s)\n",
                    name.UTF8String, kCursors[i].identifier);
            failed++;
        }
    }

    if (applied == 0 && failed == 0) {
        fprintf(stderr, "gauntlet: no matching .png files in %s (see `gauntlet list`)\n",
                dir.UTF8String);
        return 1;
    }
    printf("%d cursor(s) applied, %d failed\n", applied, failed);
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

static int resetCursors(void) {
    CGSConnectionID cid = CGSMainConnectionID();

    // Re-register stock images over anything we replaced globally
    // (legacy and Tahoe S-variant identifiers).
    restoreFromNSCursor("com.apple.coregraphics.Arrow",  [NSCursor arrowCursor]);
    restoreFromNSCursor("com.apple.coregraphics.ArrowS", [NSCursor arrowCursor]);
    restoreFromNSCursor("com.apple.coregraphics.IBeam",  [NSCursor IBeamCursor]);
    restoreFromNSCursor("com.apple.coregraphics.IBeamS", [NSCursor IBeamCursor]);

    // Drop all com.apple.cursor.N registrations and reload defaults.
    if (CoreCursorUnregisterAll(cid) == kCGErrorSuccess) {
        for (int x = 0; x < 45; x++) CoreCursorSet(cid, x);
        printf("cursors restored (a logout fully resets everything)\n");
        return 0;
    }
    fprintf(stderr, "gauntlet: CoreCursorUnregisterAll failed — log out and back in to reset\n");
    return 1;
}

#pragma mark - Cape management

// The capes/ directory lives beside the real (symlink-resolved) executable.
static NSString *capesDirectory(void) {
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    char *buf = malloc(size);
    _NSGetExecutablePath(buf, &size);
    NSString *exe = [@(buf) stringByResolvingSymlinksInPath];
    free(buf);
    return [exe.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"capes"];
}

static NSString *currentLinkPath(void) {
    return [capesDirectory() stringByAppendingPathComponent:@".current"];
}

// Name of the currently selected cape, or nil.
static NSString *currentCapeName(void) {
    NSString *target = [[NSFileManager defaultManager]
                        destinationOfSymbolicLinkAtPath:currentLinkPath() error:nil];
    return target.lastPathComponent;
}

static int useCape(NSString *name) {
    NSFileManager *fm = [NSFileManager defaultManager];

    if (!name) { // re-apply current (login agent path); no cape selected is fine
        name = currentCapeName();
        if (!name) {
            printf("no cape selected\n");
            return 0;
        }
    }

    NSString *dir = [capesDirectory() stringByAppendingPathComponent:name];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
        fprintf(stderr, "gauntlet: no cape named '%s' in %s (see `gauntlet capes`)\n",
                name.UTF8String, capesDirectory().UTF8String);
        return 1;
    }

    int result = applyDirectory(dir);
    if (result == 0) {
        [fm removeItemAtPath:currentLinkPath() error:nil];
        [fm createSymbolicLinkAtPath:currentLinkPath() withDestinationPath:name error:nil];
    }
    return result;
}

static int listCapes(void) {
    NSString *capes = capesDirectory();
    NSString *current = currentCapeName();
    NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:capes error:nil];
    int shown = 0;
    for (NSString *entry in [entries sortedArrayUsingSelector:@selector(compare:)]) {
        if ([entry hasPrefix:@"."]) continue;
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:[capes stringByAppendingPathComponent:entry]
                                             isDirectory:&isDir];
        if (!isDir) continue;
        printf("%s %s\n", [entry isEqualToString:current] ? "*" : " ", entry.UTF8String);
        shown++;
    }
    if (!shown) printf("no capes installed in %s\n", capes.UTF8String);
    return 0;
}

#pragma mark - main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *cmd = argc > 1 ? @(argv[1]) : @"";

        if ([cmd isEqualToString:@"use"]) {
            return useCape(argc > 2 ? @(argv[2]) : nil);
        }
        if ([cmd isEqualToString:@"capes"]) {
            return listCapes();
        }
        if ([cmd isEqualToString:@"apply"] && argc > 2) {
            return applyDirectory([@(argv[2]) stringByStandardizingPath]);
        }
        if ([cmd isEqualToString:@"reset"]) {
            [[NSFileManager defaultManager] removeItemAtPath:currentLinkPath() error:nil];
            return resetCursors();
        }
        if ([cmd isEqualToString:@"list"]) {
            for (int i = 0; kCursors[i].name; i++)
                printf("%-12s %s\n", kCursors[i].name, kCursors[i].identifier);
            return 0;
        }

        fprintf(stderr,
                "gauntlet — system-wide cursor replacer\n"
                "usage:\n"
                "  gauntlet use <name>    apply cape capes/<name> and make it current\n"
                "  gauntlet use           re-apply the current cape\n"
                "  gauntlet capes         list installed capes (* = current)\n"
                "  gauntlet apply <dir>   apply <name>.png (+ optional <name>@2x.png,\n"
                "                         hotspots.json) from any directory\n"
                "  gauntlet reset         restore stock cursors, clear current cape\n"
                "  gauntlet list          list supported cursor names\n");
        return argc <= 1 ? 0 : 1;
    }
}
