#import "Core/Runtime/DYPlusRuntime.h"
#import <math.h>

NSString *DYPlusPreferenceString(NSString *key) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}
#import <string.h>

BOOL DYPlusReadBooleanSelector(id object, SEL selector, BOOL *value) {
    if (!object || !value || ![object respondsToSelector:selector]) return NO;
    @try {
        NSMethodSignature *signature = [object methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 2) return NO;
        const char *type = signature.methodReturnType;
        while (*type && strchr("rnNoORV", *type)) type++;
        if (!*type || (*type != '@' && !strchr("BcCsSiIlLqQ", *type))) return NO;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = object;
        invocation.selector = selector;
        [invocation invoke];
        if (*type == '@') {
            __unsafe_unretained id result = nil;
            [invocation getReturnValue:&result];
            if (![result isKindOfClass:NSNumber.class] && ![result isKindOfClass:NSString.class]) return NO;
            *value = [result boolValue];
        } else {
            // 只接受整数/BOOL 返回类型，不能把标量当成 Objective-C 对象发消息。
            uint64_t result = 0;
            if (signature.methodReturnLength > sizeof(result)) return NO;
            [invocation getReturnValue:&result];
            *value = result != 0;
        }
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}

id DYPlusUnarchiveObject(NSData *data, NSSet<Class> *classes) {
    if (![data isKindOfClass:NSData.class] || data.length == 0 || data.length > 8 * 1024 * 1024) return nil;
    @try {
        return [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
    } @catch (__unused NSException *exception) { return nil; }
}

UIColor *DYPlusUnarchiveColor(NSData *data) {
    id object = DYPlusUnarchiveObject(data, [NSSet setWithObject:UIColor.class]);
    return [object isKindOfClass:UIColor.class] ? object : nil;
}

NSMutableDictionary<NSString *, NSNumber *> *DYPlusUnarchiveUsageStats(NSData *data) {
    id object = DYPlusUnarchiveObject(data, [NSSet setWithObjects:NSDictionary.class, NSMutableDictionary.class, NSString.class, NSNumber.class, nil]);
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (![object isKindOfClass:NSDictionary.class] || [object count] > 512) return result;
    for (id key in object) {
        id value = object[key];
        if ([key isKindOfClass:NSString.class] && [key length] <= 128 && [value isKindOfClass:NSNumber.class]) {
            double count = [value doubleValue];
            if (isfinite(count) && count == trunc(count) && count >= 0 && count <= 1000000000) result[key] = value;
        }
    }
    return result;
}
