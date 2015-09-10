#import "NSStringExtension.h"

@implementation NSString (Extension)

- (NSString *)stringByAppendingPathComponents:(NSString *)str, ... {
	va_list arguments;
	NSString *resultString = self;
	NSString *string;
	
	if (str) {
		resultString = [resultString stringByAppendingPathComponent:str];
		va_start(arguments, str);
		while ((string = va_arg(arguments, id))) {
			resultString = [resultString stringByAppendingPathComponent:string];			
		}
		va_end(arguments);
	}
	
	return resultString;
}


@end
