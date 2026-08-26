//
//  dump_cursors.m — writes every registered core cursor to <outdir>/NN.png and
//  prints "N width height frameCount" per cursor. Used to build CURSORS.md.
//  Run with cursors reset to stock to document the system set.
//
@import AppKit;
@import ApplicationServices;
typedef int CGSConnectionID;
typedef int CGSCursorID;
CG_EXTERN CGSConnectionID CGSMainConnectionID(void);
CG_EXTERN CGError CoreCursorSet(CGSConnectionID cid, CGSCursorID c);
CG_EXTERN CGError CGSCopyRegisteredCursorImages(CGSConnectionID cid, char *name,
    CGSize *size, CGPoint *hot, NSUInteger *frames, CGFloat *dur, CFArrayRef *imgs);

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *out = @(argv[1]);
        [NSFileManager.defaultManager createDirectoryAtPath:out
            withIntermediateDirectories:YES attributes:nil error:nil];
        CGSConnectionID cid = CGSMainConnectionID();
        for (int i = 0; i <= 44; i++) CoreCursorSet(cid, i);  // force registration

        for (int i = 0; i <= 44; i++) {
            char name[64];
            snprintf(name, sizeof name, "com.apple.cursor.%d", i);
            CGSize sz; CGPoint hot; NSUInteger fr; CGFloat dur; CFArrayRef imgs = NULL;
            if (CGSCopyRegisteredCursorImages(cid, name, &sz, &hot, &fr, &dur, &imgs)
                != kCGErrorSuccess || !imgs || !CFArrayGetCount(imgs)) continue;
            CGImageRef img = (CGImageRef)CFArrayGetValueAtIndex(imgs, 0);
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [png writeToFile:[out stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%02d.png", i]] atomically:YES];
            // machine-readable: make_sheet.py reads these columns
            printf("%d %.0f %.0f %lu\n", i, sz.width, sz.height, (unsigned long)fr);
            CFRelease(imgs);
        }
    }
    return 0;
}
