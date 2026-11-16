#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Calls are serialized by SystemDictionaryReader. The active list is loaded once per process.
NSArray<NSDictionary<NSString *, id> *> *ZDSystemDictionaryEntries(NSString *term);
NSUInteger ZDSystemDictionaryCount(void);
NS_ASSUME_NONNULL_END
