//
//  main.m
//  zooboomafoo
//
//  Created by Jack Flintermann on 10/2/19.
//  Copyright © 2019 Jack. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ApplicationServices/ApplicationServices.h>
#import <AppKit/AppKit.h>
#include <Carbon/Carbon.h>
#import <Quartz/Quartz.h>

void postKeyCode(CGKeyCode keyCode, NSRunningApplication *app, BOOL controlDown, NSInteger windowNumber) {
    NSEventModifierFlags flags = controlDown ? NSEventModifierFlagCommand : 0;

    CGEventRef event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:CGPointZero modifierFlags:flags timestamp:kCFAbsoluteTimeIntervalSince1970 windowNumber:windowNumber context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:keyCode].CGEvent;
    CGEventPostToPid(app.processIdentifier, event);
    CFRelease(event);
    
    CGEventRef event2 = [NSEvent keyEventWithType:NSEventTypeKeyUp location:CGPointZero modifierFlags:flags timestamp:kCFAbsoluteTimeIntervalSince1970 windowNumber:windowNumber context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:keyCode].CGEvent;
    CGEventPostToPid(app.processIdentifier, event2);
    CFRelease(event2);
}

void scrollZoomToTheRight(NSRunningApplication *zoom, NSInteger windowNumber) {
    for (int i = 0; i < 10; i++) {
        postKeyCode(kVK_RightArrow, zoom, NO, windowNumber); // far right
    }
}

NSDictionary *extractWindowInfo(NSRunningApplication *zoom) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    for (int i = 0; i < CFArrayGetCount(windowList); i++) {
        CFDictionaryRef windowInfo = CFArrayGetValueAtIndex(windowList, i);
        NSNumber *windowOwner = (NSNumber *)(CFDictionaryGetValue(windowInfo, kCGWindowOwnerPID));
        NSNumber *windowNumber = (NSNumber *)(CFDictionaryGetValue(windowInfo, kCGWindowNumber));
        NSString *windowName = (NSString *)(CFDictionaryGetValue(windowInfo, kCGWindowName));
        if ([windowOwner isEqualToNumber:@(zoom.processIdentifier)]) {
            [info setValue:windowNumber forKey:windowName];
        }
    }
    return info;
}

NSDictionary* setupZoom(NSRunningApplication *zoom) {
    [zoom activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    
    NSDictionary *info = extractWindowInfo(zoom);
    NSInteger mainWindow = [[info valueForKey:@"Zoom"] integerValue];

    postKeyCode(kVK_ANSI_Comma, zoom, YES, mainWindow); // open prefs
    info = extractWindowInfo(zoom);
    mainWindow = [[info valueForKey:@"Zoom"] integerValue];
    NSInteger settingsWindow = [[info valueForKey:@"Settings"] integerValue];
    
    postKeyCode(kVK_Tab, zoom, NO, settingsWindow); // ensure prefs are active
    for (int i = 0; i < 10; i++) {
        postKeyCode(kVK_UpArrow, zoom, NO, settingsWindow); // move to top
    }
    for (int i = 0; i < 4; i++) {
        postKeyCode(kVK_DownArrow, zoom, NO, settingsWindow); // move to virtual background
    }
    postKeyCode(kVK_Return, zoom, NO, settingsWindow); // select virtual background
    postKeyCode(kVK_Tab, zoom, NO, settingsWindow); // focus settings pane
    postKeyCode(kVK_DownArrow, zoom, NO, settingsWindow); // ensure bottom row
    scrollZoomToTheRight(zoom, settingsWindow);
    return info;
}

void toggleFrame(int frame, NSRunningApplication *zoom, NSInteger window) {
    if (frame % 2 == 0) {
        postKeyCode(kVK_LeftArrow, zoom, NO, window);
    } else {
        postKeyCode(kVK_RightArrow, zoom, NO, window);
    }
}

void loadContentsForFrame(int frame, NSString *frameDirectory, NSArray *zoomFilePaths) {
    NSString *imagePath = [frameDirectory stringByAppendingFormat:@"/%05d.png", frame];
    for (NSString *path in zoomFilePaths) {
        NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
        [imageData writeToFile:path atomically:YES];
    }
}

NSTimeInterval unpack(NSString *gifPath, NSString *destinationDir) {
    NSString *filename = [gifPath lastPathComponent];
    NSString *destinationFilename = [destinationDir stringByAppendingPathComponent:filename];
    
    NSTask *identify = [NSTask new];
    identify.launchPath = @"/usr/local/bin/identify";
    identify.arguments = @[@"-format", @"%T\n", gifPath];
    NSPipe *output = [NSPipe pipe];
    identify.standardOutput = output;
    [identify launch];
    [identify waitUntilExit];
    NSFileHandle *read = [output fileHandleForReading];
    NSData *data = [read readDataToEndOfFile];
    NSString *contents = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSTimeInterval centiseconds = [[[contents componentsSeparatedByString:@"\n"] firstObject] doubleValue]; // yup
    NSTimeInterval duration =  centiseconds / 100;
    if (duration < 0.02) {
        duration = 0.02;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:destinationFilename]) {
//        return duration; // cache the gif in the tmpdir to save time
    }
    [[NSTask launchedTaskWithLaunchPath:@"/bin/rm" arguments:@[@"-rf", destinationDir]] waitUntilExit];
    [[NSTask launchedTaskWithLaunchPath:@"/bin/mkdir" arguments:@[destinationDir]] waitUntilExit];
    [[NSTask launchedTaskWithLaunchPath:@"/usr/local/bin/convert" arguments:@[gifPath, @"-coalesce", [destinationDir stringByAppendingString:@"/%05d.png"]]] waitUntilExit];
    [[NSFileManager defaultManager] copyItemAtPath:gifPath toPath:destinationFilename error:nil];
    return duration;
}


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if (args.count != 2) {
            NSLog(@"usage: zooboomafoo PATH_TO_GIF");
            return 1;
        }

        NSString *identifier = @"us.zoom.xos";
        NSRunningApplication *zoom = [[NSRunningApplication runningApplicationsWithBundleIdentifier:identifier] firstObject];
        if (!zoom) {
            NSLog(@"Zoom doesn't appear to be running?");
            return 1;
        }
        
        NSDictionary* opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
        BOOL hasAccess = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
        if (!hasAccess) {
            NSLog(@"zooboomafoo needs accessibility controls to run. please go to system prefs and enable it.");
            return 1;
        }
        
        NSString *GIF_PATH = [args.lastObject stringByStandardizingPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:GIF_PATH]) {
            NSLog(@"There doesn't seem to be a GIF there.");
            return 1;
        }
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/local/bin/convert"]) {
            NSLog(@"You don't seem to have imagemagick installed. Please run `brew install imagemagick`.");
            return 1;
        }
        NSString *ZOOM_DIR = [[@"~/Library/Application Support/zoom.us/data/VirtualBkgnd_Default" stringByStandardizingPath] stringByReplacingOccurrencesOfString:@" " withString:@"\ "];
        NSString *ZOOM_TMPDIR = [ZOOM_DIR stringByAppendingPathComponent:@"tmp"];
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:ZOOM_DIR] includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsSubdirectoryDescendants|NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
        NSMutableArray *ZOOM_IMAGE_PATHS = [NSMutableArray array];
        for (NSURL *fileURL in enumerator) {
            NSString *fileName;
            [fileURL getResourceValue:&fileName forKey:NSURLNameKey error:nil];
            NSNumber *isDirectory;
            [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
            if (!isDirectory.boolValue) {
                [ZOOM_IMAGE_PATHS addObject:fileURL.path];
            }
        }
        
        CGFloat duration = unpack(GIF_PATH, ZOOM_TMPDIR);
        NSUInteger frameCount = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:ZOOM_TMPDIR error:nil] count];
        
        setupZoom(zoom);
        NSDictionary *info = extractWindowInfo(zoom);
        NSInteger settingsWindow = [[info valueForKey:@"Settings"] integerValue];

        for (int frame = 0; frame < frameCount; frame = (frame + 1) % frameCount) {
            if (frame == 0) {
                scrollZoomToTheRight(zoom, settingsWindow);
            }
            loadContentsForFrame(frame, ZOOM_TMPDIR, ZOOM_IMAGE_PATHS);
            toggleFrame(frame, zoom, settingsWindow);
            [NSThread sleepForTimeInterval:duration];
        }
    }
    return 0;
}
