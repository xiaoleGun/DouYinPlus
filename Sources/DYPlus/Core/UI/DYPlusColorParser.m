#import "Core/UI/DYPlusColorParser.h"

static UIColor *DYPlusPlainColor(NSString *text) {
    NSString *value = [text hasPrefix:@"#"] ? [text substringFromIndex:1] : text;
    if ([value isEqualToString:@"random"])
        return [UIColor colorWithRed:arc4random_uniform(256)/255.0 green:arc4random_uniform(256)/255.0 blue:arc4random_uniform(256)/255.0 alpha:1];
    if (value.length == 3) {
        value = [NSString stringWithFormat:@"%C%C%C%C%C%C", [value characterAtIndex:0], [value characterAtIndex:0],
            [value characterAtIndex:1], [value characterAtIndex:1], [value characterAtIndex:2], [value characterAtIndex:2]];
    }
    if (value.length != 6 && value.length != 8) return UIColor.blackColor;
    static NSCharacterSet *invalidHex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ invalidHex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet; });
    if ([value rangeOfCharacterFromSet:invalidHex].location != NSNotFound) return UIColor.blackColor;
    unsigned long long number = 0;
    if (![[NSScanner scannerWithString:value] scanHexLongLong:&number]) return UIColor.blackColor;
    CGFloat alpha = value.length == 8 ? ((number >> 24) & 255) / 255.0 : 1;
    return [UIColor colorWithRed:((number >> 16) & 255)/255.0 green:((number >> 8) & 255)/255.0 blue:(number & 255)/255.0 alpha:alpha];
}

UIColor *DYPlusColorFromString(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length > 128) return UIColor.blackColor;
    NSString *key = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    static NSCache<NSString *, UIColor *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 32;
        cache.totalCostLimit = 4 * 1024 * 1024;
    });
    BOOL random = [key containsString:@"random"];
    UIColor *cached = random ? nil : [cache objectForKey:key];
    if (cached) return cached;
    NSArray *parts = [key componentsSeparatedByString:@","];
    NSArray *colors = nil;
    if ([key isEqualToString:@"rainbow"] || [key isEqualToString:@"#rainbow"]) {
        colors = @[UIColor.redColor, UIColor.orangeColor, UIColor.yellowColor, UIColor.greenColor, UIColor.cyanColor, UIColor.blueColor, UIColor.purpleColor];
    } else if (parts.count == 2) {
        NSString *first = [parts[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *second = [parts[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        colors = @[DYPlusPlainColor(first), DYPlusPlainColor(second)];
    }
    UIColor *result = nil;
    NSUInteger cost = 1;
    if (colors) {
        NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count];
        for (UIColor *color in colors) [cgColors addObject:(__bridge id)color.CGColor];
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1; // 渐变无细节纹理，无需每次建立 3x 的大位图。
        format.opaque = NO;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(400,100) format:format];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)cgColors, NULL);
            if (gradient) {
                CGContextDrawLinearGradient(context.CGContext, gradient, CGPointMake(0,50), CGPointMake(400,50), 0);
                CGGradientRelease(gradient);
            }
            CGColorSpaceRelease(space);
        }];
        result = [UIColor colorWithPatternImage:image];
        cost = 400 * 100 * 4;
    } else result = DYPlusPlainColor(key);
    if (!random) [cache setObject:result forKey:key cost:cost];
    return result;
}
