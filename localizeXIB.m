#import <Foundation/Foundation.h>
#import "NSStringExtension.h"

int localizeXIB(NSArray *parameters);
void copyFile(NSString *source, NSString *destination);
NSDate *modificationDateForFile(NSString *path);
void writeStringsFile(NSDictionary *dictionary, NSString *file);


char usage[] = "Usage: localizeXIB [-l] [-i <ignore file>] <source xib> <language> ...\n";
NSString *ignoreFile = nil;


int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	int index = 1, function = 0, exitcode;
	
	for (; index < argc; index++) {
		if (argv[index][0] == '-') {
			switch (argv[index][1]) {
				case 'l': //LocalizeXIB
				case 'i':
					if (++index >= argc) goto usage;
					ignoreFile = [NSString stringWithUTF8String:argv[index]];
					if (![[NSFileManager defaultManager] fileExistsAtPath:ignoreFile]) {
						fprintf(stderr, "Invalid ignore file!");
						return 2;
					}
					
					break;
				case 'h':
					goto usage;
				default:
					goto usage;
			}
		} else {
			break;
		}
	}
	
	
	if (argc - index < 2) {
		printf("%s", usage);
		return 1;
	}
	
	
	
	
	NSMutableArray *parameters = [NSMutableArray arrayWithCapacity:argc - index];
	for (; index < argc; index++) {
		[parameters addObject:[NSString stringWithUTF8String:argv[index]]];
	}
	
	switch (function) {
		default:
			exitcode = localizeXIB(parameters);
			break;
	}
	[pool drain];
	return exitcode;
	
usage:
	printf("%s", usage);
	[pool drain];
	return 1;
}



// <Source_XIB> <language> ...
int localizeXIB(NSArray *parameters) {	
	@try {
		NSString *sourceXib = [parameters objectAtIndex:0];
		NSString *xibName = [sourceXib lastPathComponent];
		NSString *stringsName = [xibName stringByAppendingPathExtension:@"strings"];
		NSString *sourceDir = [sourceXib stringByDeletingLastPathComponent];
		NSString *resourcesDir = [sourceDir stringByDeletingLastPathComponent];
		NSString *sourceLanguage = [sourceDir lastPathComponent];
		NSString *sourceStringsFile = [sourceDir stringByAppendingPathComponent:stringsName];
		NSString *targetStringsFile;
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSString *language;
		NSMutableDictionary *targetStringsDictionary;
		
		
		if (![fileManager fileExistsAtPath:sourceXib]) {
			fprintf(stderr, "Source XIB-file not found!\n");
			return 1;
		}
		
		
		NSUInteger i = 1, count = [parameters count];
		NSMutableArray *targetLanguagesTodo = [NSMutableArray arrayWithCapacity:count - 1];
		for (; i < count; i++) {
			language = [parameters objectAtIndex:i];
			if (![language hasSuffix:@".lproj"]) {
				language = [language stringByAppendingPathExtension:@"lproj"];
			}
			if ([language isEqualToString:sourceLanguage]) {
				fprintf(stderr, "Source XIB-file and target language can’t be identical!\n");
				return 1;
			}
			[targetLanguagesTodo addObject:language];
		}
		NSArray *targetLanguages = [NSArray arrayWithArray:targetLanguagesTodo];
		
		
		printf("Localizing %s\n", [xibName UTF8String]);
		
		
		NSDate *sourceXibDate = modificationDateForFile(sourceXib);
		
		
		// Generate .strings for the source language if needed.
		BOOL generateStringsFile;
		if ([fileManager fileExistsAtPath:sourceStringsFile]) {
			generateStringsFile = [sourceXibDate compare:modificationDateForFile(sourceStringsFile)] == NSOrderedDescending;
		} else {
			generateStringsFile = YES;
		}
		
		if (generateStringsFile) {
			printf("Generate source .strings file\n");
			
			NSTask *ibtoolTask = [[[NSTask alloc] init] autorelease];
			[ibtoolTask setLaunchPath:@"/usr/bin/ibtool"];
			[ibtoolTask setArguments:[NSArray arrayWithObjects:@"--generate-stringsfile", sourceStringsFile, sourceXib, nil]];
			[ibtoolTask launch];
			[ibtoolTask waitUntilExit];
			if ([ibtoolTask terminationStatus] != 0) {
				fprintf(stderr, "ibtool --generate-stringsfile failed!\n");
				return 2;
			}
		}
		
		
		// Create the set of ignored strings.
		NSMutableSet *ignoredStrings = [NSMutableSet setWithObject:@""];
		if (ignoreFile) {
			// The ignore-file contains one string per line.
			NSString *stringsToIgnore = [NSString stringWithContentsOfFile:ignoreFile encoding:NSUTF8StringEncoding error:nil];
			if (!stringsToIgnore) {
				fprintf(stderr, "\"%s\" can't be read!\n", [ignoreFile UTF8String]);
				return 1;
			}
			
			[ignoredStrings addObjectsFromArray:[stringsToIgnore componentsSeparatedByString:@"\n"]];
		}
		
		
		// Load the dictionary from the source .strings files.
		NSMutableDictionary *sourceStringsDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:sourceStringsFile];
		if (!sourceStringsDictionary) {
			fprintf(stderr, "\"%s\" can't be read!\n", [sourceStringsFile UTF8String]);
			return 1;
		}
		
		
		// Remove ignored strings from the source .strings file.
		NSMutableArray *keysToRemove = [NSMutableArray array];
		
		for (NSString *ignoredString in ignoredStrings) {
			[keysToRemove addObjectsFromArray:[sourceStringsDictionary allKeysForObject:ignoredString]];
		}
		
		if ([keysToRemove count]) {
			printf("Clean source .strings file\n");

			[sourceStringsDictionary removeObjectsForKeys:keysToRemove];
			writeStringsFile(sourceStringsDictionary, sourceStringsFile);
		}
		NSSet *keysInSourceStrings = [NSSet setWithArray:[sourceStringsDictionary allKeys]];
		
		
		// Load the dictionarys from the destination .strings files.
		NSMutableDictionary *targetStringsDictionarys = [NSMutableDictionary dictionaryWithCapacity:[targetLanguages count]]; // Dictionary of dictionarys! key = language.
		
		for (language in targetLanguages) {
			targetStringsFile = [resourcesDir stringByAppendingPathComponents:language, stringsName, nil];
			
			if ([fileManager fileExistsAtPath:targetStringsFile]) {
				targetStringsDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:targetStringsFile];
				if (!targetStringsDictionary) {
					fprintf(stderr, "\"%s\" can't be read!\n", [targetStringsFile UTF8String]);
					return 1;
				}
				
				
				// Remove the keys which are not in the source .strings file.
				NSMutableSet *keys = [NSMutableSet setWithArray:[targetStringsDictionary allKeys]];
				[keys minusSet:keysInSourceStrings];
				[keys addObjectsFromArray:[targetStringsDictionary allKeysForObject:@""]]; // Also remove empty entrys.
				
				if ([keys count]) {
					printf("Clean \"%s\" .strings file\n", [language UTF8String]);
					
					[targetStringsDictionary removeObjectsForKeys:[keys allObjects]];
					writeStringsFile(targetStringsDictionary, targetStringsFile);
				}
				
				// Add the dictionary to the "list".
				[targetStringsDictionarys setObject:targetStringsDictionary forKey:language]; 
			} else {
				fprintf(stderr, "\"%s\" not found!\n", [targetStringsFile UTF8String]);
				return 1;
			}
		}
		
		
		
		// Localize the XIBs.
		NSString *oldXib = [resourcesDir stringByAppendingPathComponents:@"old", sourceLanguage, xibName, nil];
		BOOL oldSourceXibExists = [fileManager fileExistsAtPath:oldXib];
		
		for (language in targetLanguages) {
			BOOL updateXib = NO;
			BOOL incremental = NO;
			NSString *languageDir = [resourcesDir stringByAppendingPathComponent:language];
			NSString *targetXib = [languageDir stringByAppendingPathComponent:xibName];
			targetStringsFile = [languageDir stringByAppendingPathComponent:stringsName];
			
			
			if (![fileManager fileExistsAtPath:targetXib]) {
				copyFile(sourceXib, targetXib);
				updateXib = YES;
			} else {
				incremental = oldSourceXibExists;
				// Is the source XIB or the destionation .strings file newer than destionation XIB?
				NSDate *date = modificationDateForFile(targetXib);
				updateXib = ([sourceXibDate compare:date] == NSOrderedDescending) || ([modificationDateForFile(targetStringsFile) compare:date] == NSOrderedDescending);
			}
			
			
			if (updateXib) {
				printf("Update \"%s\" xib\n", [language UTF8String]);
				
				NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:10];
				if (incremental) {
					[arguments addObject:@"--previous-file"];
					[arguments addObject:oldXib];
					[arguments addObject:@"--incremental-file"];
					[arguments addObject:targetXib];
					[arguments addObject:@"--localize-incremental"];
				}
				[arguments addObject:@"--strings-file"];
				[arguments addObject:[resourcesDir stringByAppendingPathComponents:language, stringsName, nil]];
				[arguments addObject:@"--write"];
				[arguments addObject:targetXib];
				[arguments addObject:sourceXib];
				
				NSTask *ibtoolTask = [[[NSTask alloc] init] autorelease];
				[ibtoolTask setLaunchPath:@"/usr/bin/ibtool"];
				[ibtoolTask setArguments:arguments];
				[ibtoolTask launch];
				[ibtoolTask waitUntilExit];
				if ([ibtoolTask terminationStatus] != 0) {
					fprintf(stderr, "ibtool --write failed!\n");
					return 2;
				}
			}
		}
		
		if (!oldSourceXibExists || [sourceXibDate compare:modificationDateForFile(oldXib)] == NSOrderedDescending) {
			copyFile(sourceXib, oldXib);
		}
		
		printf("Localization succeeded\n");
	}
	@catch (NSException *e) {
		fprintf(stderr, "Error: %s", [[e description] UTF8String]);
		return 2;
	}
	
    return 0;
}



void writeStringsFile(NSDictionary *dictionary, NSString *file) {
	NSMutableString *string = [NSMutableString string];
	NSArray *keys = [[dictionary allKeys] sortedArrayUsingComparator:^NSComparisonResult(id str1, id str2) {
		return [str1 compare:str2 options:NSNumericSearch];
	}];
	
	for (NSString *key in keys) {
		NSString *value = [dictionary objectForKey:key];
		
		[string appendFormat:@"\"%@\" = \"%@\";\n", key, value];
	}
	
	NSError *error = nil;
	[string writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&error];
	
	if (error) {
		@throw [NSException exceptionWithName:@"NSError" reason:[error.userInfo objectForKey:NSLocalizedDescriptionKey] userInfo:error.userInfo];
	}
}

void copyFile(NSString *source, NSString *destination) {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError *anError = nil;
	if ([fileManager fileExistsAtPath:destination]) {
		if (![fileManager removeItemAtPath:destination error:&anError]) {
			[[NSException exceptionWithName:@"fileRemoveException" reason:[anError description] userInfo:[anError userInfo]] raise];
		}
	} else {
		NSString *dir = [destination stringByDeletingLastPathComponent];
		if (![fileManager fileExistsAtPath:dir]) {
			if (![fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&anError]) {
				[[NSException exceptionWithName:@"createDirectoryException" reason:[anError description] userInfo:[anError userInfo]] raise];
			}		
		}
	}
	if (![fileManager copyItemAtPath:source toPath:destination error:&anError]) {
		[[NSException exceptionWithName:@"copyItemException" reason:[anError description] userInfo:[anError userInfo]] raise];
	}
}

NSDate *modificationDateForFile(NSString *path) {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError *anError = nil;
	NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:&anError];
	if (anError) {
		[[NSException exceptionWithName:@"getAttributesException" reason:[anError description] userInfo:[anError userInfo]] raise];
	}
	return [attributes objectForKey:@"NSFileModificationDate"];
}



