#import "SystemDictionaryBridge.h"
#import <CoreServices/CoreServices.h>
extern CFArrayRef DCSGetActiveDictionaries(void);
extern CFArrayRef DCSCopyRecordsForSearchString(DCSDictionaryRef, CFStringRef, unsigned long long, long long);
extern CFStringRef DCSDictionaryGetName(DCSDictionaryRef);
extern CFStringRef DCSDictionaryGetIdentifier(DCSDictionaryRef);
extern CFURLRef DCSDictionaryGetURL(DCSDictionaryRef);
extern CFStringRef DCSRecordCopyData(CFTypeRef, long);
extern CFStringRef DCSRecordGetHeadword(CFTypeRef);
static NSArray *activeDictionaries(void) {
    static NSArray *dictionaries;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dictionaries = CFBridgingRelease(DCSGetActiveDictionaries()) ?: @[]; });
    return dictionaries;
}
NSUInteger ZDSystemDictionaryCount(void) { return activeDictionaries().count; }
NSArray<NSDictionary<NSString *, id> *> *ZDSystemDictionaryEntries(NSString *term) {
    NSMutableArray *entries = [NSMutableArray array];
    for (id item in activeDictionaries()) {
        DCSDictionaryRef dictionary = (__bridge DCSDictionaryRef)item;
        NSURL *url = (__bridge NSURL *)DCSDictionaryGetURL(dictionary);
        if (!url) continue;
        NSArray *records = CFBridgingRelease(DCSCopyRecordsForSearchString(dictionary, (__bridge CFStringRef)term, 0, 0));
        for (id record in records) {
            // DictionaryServices version 1 returns entry HTML with its original app stylesheet.
            NSString *html = CFBridgingRelease(DCSRecordCopyData((__bridge CFTypeRef)record, 1));
            if (!html.length) continue;
            [entries addObject:@{@"identifier": (__bridge NSString *)DCSDictionaryGetIdentifier(dictionary),
                @"name": (__bridge NSString *)DCSDictionaryGetName(dictionary), @"url": url,
                @"headword": (__bridge NSString *)DCSRecordGetHeadword((__bridge CFTypeRef)record) ?: term,
                @"html": html}];
        }
    }
    return entries;
}
