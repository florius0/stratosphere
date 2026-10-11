#import "DisplayProbeBridge.h"
// Private selector declarations verified against Chromium's CoreGraphics
// helper:
// https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm
// Runtime lookup keeps private classes out of the link contract. Live macOS 26
// qualification is required; declarations alone do not establish availability.
@protocol STDescriptor
@property unsigned int vendorID;
@property unsigned int productID;
@property unsigned int serialNum;
@property unsigned int serialNumber;
@property(strong) NSString *name;
@property CGSize sizeInMillimeters;
@property unsigned int maxPixelsWide;
@property unsigned int maxPixelsHigh;
@property CGPoint redPrimary;
@property CGPoint greenPrimary;
@property CGPoint bluePrimary;
@property CGPoint whitePoint;
@property(strong) id queue;
@end
@protocol STDisplay
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property(readonly) unsigned int displayID;
@end
@protocol STSettings
@property(strong) NSArray *modes;
@property unsigned int hiDPI;
@property unsigned int rotation;
@end
@protocol STMode
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)rate;
@end
@interface STVirtualDisplay ()
@property(strong) id<STDisplay> native;
@end
@implementation STVirtualDisplay
+ (instancetype)createWithWidth:(unsigned int)width
                         height:(unsigned int)height
                          hiDPI:(BOOL)hiDPI
                         serial:(unsigned int)serial
                          error:(NSError **)error {
  @try {
    Class dc = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class vc = NSClassFromString(@"CGVirtualDisplay");
    Class sc = NSClassFromString(@"CGVirtualDisplaySettings");
    Class mc = NSClassFromString(@"CGVirtualDisplayMode");
    if (!dc || !vc || !sc || !mc)
      @throw [NSException
          exceptionWithName:@"Unavailable"
                     reason:@"CGVirtualDisplay runtime classes unavailable"
                   userInfo:nil];
    id<STDescriptor> descriptor = [dc new];
    for (NSString *selector in @[
           @"setVendorID:", @"setProductID:", @"setSerialNum:",
           @"setSerialNumber:", @"setName:", @"setSizeInMillimeters:",
           @"setMaxPixelsWide:", @"setMaxPixelsHigh:", @"setRedPrimary:",
           @"setGreenPrimary:", @"setBluePrimary:", @"setWhitePoint:",
           @"setQueue:"
         ]) {
      if (![(id)descriptor respondsToSelector:NSSelectorFromString(selector)])
        @throw [NSException exceptionWithName:@"Unavailable"
                                       reason:selector
                                     userInfo:nil];
    }
    descriptor.vendorID = 505;
    descriptor.productID = 1;
    descriptor.serialNum = serial;
    descriptor.serialNumber = serial;
    descriptor.name =
        [NSString stringWithFormat:@"Stratosphere Fixture %u", serial];
    descriptor.maxPixelsWide = width;
    descriptor.maxPixelsHigh = height;
    double density = hiDPI ? 220 : 110;
    descriptor.sizeInMillimeters =
        CGSizeMake(width * 25.4 / density, height * 25.4 / density);
    descriptor.redPrimary = CGPointMake(0.64, 0.33);
    descriptor.greenPrimary = CGPointMake(0.30, 0.60);
    descriptor.bluePrimary = CGPointMake(0.15, 0.06);
    descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
    descriptor.queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    id<STDisplay> native =
        [(id<STDisplay>)[vc alloc] initWithDescriptor:descriptor];
    if (!native || ![(id)native respondsToSelector:@selector(applySettings:)] ||
        ![(id)native respondsToSelector:@selector(displayID)])
      @throw [NSException exceptionWithName:@"Unavailable"
                                     reason:@"CGVirtualDisplay creation failed"
                                   userInfo:nil];
    id<STMode> mode =
        [(id<STMode>)[mc alloc] initWithWidth:hiDPI ? width / 2 : width
                                       height:hiDPI ? height / 2 : height
                                  refreshRate:60];
    id<STSettings> settings = [sc new];
    settings.modes = @[ (id)mode ];
    settings.hiDPI = hiDPI ? 1 : 0;
    settings.rotation = 0;
    if (![native applySettings:settings] || native.displayID == 0)
      @throw [NSException exceptionWithName:@"Unavailable"
                                     reason:@"CGVirtualDisplay settings failed"
                                   userInfo:nil];
    STVirtualDisplay *result = [STVirtualDisplay new];
    result.native = native;
    return result;
  } @catch (NSException *exception) {
    if (error)
      *error = [NSError errorWithDomain:@"Stratosphere.DisplayProbe"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey : exception.reason
                                     ?: exception.name
                               }];
    return nil;
  }
}
- (CGDirectDisplayID)displayID {
  return self.native.displayID;
}
- (void)releaseDisplay {
  self.native = nil;
}
@end
