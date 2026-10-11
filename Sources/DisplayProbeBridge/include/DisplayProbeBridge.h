#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface STVirtualDisplay : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
+ (nullable instancetype)createWithWidth:(unsigned int)width
                                  height:(unsigned int)height
                                   hiDPI:(BOOL)hiDPI
                                  serial:(unsigned int)serial
                                   error:(NSError **)error;
- (void)releaseDisplay;
@end
NS_ASSUME_NONNULL_END
