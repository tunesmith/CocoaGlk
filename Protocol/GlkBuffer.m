//
//  GlkBuffer.m
//  CocoaGlk
//
//  Created by Andrew Hunter on 18/03/2005.
//  Copyright 2005 Andrew Hunter. All rights reserved.
//

#import "GlkBuffer.h"

#define GlkBigBuffer 256

@implementation GlkBuffer

// = Initialisation =

- (id) init {
	self = [super init];
	
	if (self) {
		operations = [[NSMutableArray alloc] init];
	}
	
	return self;
}

- (void) dealloc {
	[operations release];
	
	[super dealloc];
}

// = Buffering =

static NSString* stringFromOp(NSInvocation* op) {
	if ([op selector] == @selector(putChar:toStream:)) {
		unichar ch;
		
		[op getArgument: &ch
				atIndex: 2];
		if (ch < 32) return nil;
		
		return [NSString stringWithCharacters: &ch
									   length: 1];
	} else if ([op selector] == @selector(putString:toStream:)) {
		NSString* str;
		
		[op getArgument: &str
				atIndex: 2];
		
		return str;
	}
	
	return nil;
}


- (void) addOperation: (NSInvocation*) op {
	// If the last operation was writing to a stream, then we might be able to merge it with this operation
	if (([op selector] == @selector(putChar:toStream:) ||
		[op selector] == @selector(putString:toStream:) ||
		[op selector] == @selector(putData:toStream:))) {
#if 0
		// (Commented out, this currently screws up when concatenating, as we don't want to keep copying the data there)
		// We're probably OK, though, as it's bad practice to pass in data to one of these calls that can change
		// For data operations, ensure that the NSData object is not mutable (or is a copy)
		if ([op selector] == @selector(putData:toStream:)) {
			NSData* opData;
			[op getArgument: &opData
					atIndex: 2];
			
			if ([opData isKindOfClass: [NSMutableData class]]) {
				opData = [[opData copy] autorelease];
				[op setArgument: &opData
						atIndex: 2];
			}
		}
#endif
		
		int opPos = [operations count] - 1;
		NSInvocation* lastOp = [operations lastObject];
		int stream, lastStream;
		
		while (lastOp && ([lastOp selector] == @selector(putChar:toStream:) ||
						  [lastOp selector] == @selector(putString:toStream:) ||
						  [lastOp selector] == @selector(putData:toStream:))) {
			// Skip backwards past 'ignorable' selectors until we find a write to this stream
			[op getArgument: &stream
					atIndex: 3];
			[lastOp getArgument: &lastStream
						atIndex: 3];
			
			if (stream == lastStream) break;	// We've found the 'interesting' operation
			
			// Go back to the previous operation
			if (opPos > 0) {
				opPos--;
				lastOp = [operations objectAtIndex: opPos];
			} else {
				lastOp = nil;
			}
		}
		
		if (lastOp &&
			([lastOp selector] == @selector(putChar:toStream:) ||
			 [lastOp selector] == @selector(putString:toStream:)) &&
			[op selector] != @selector(putData:toStream:) &&
			stream == lastStream) {
			// If both of these have the same stream identifier, then we might be able to merge them into one operation
			NSString* lastString, *string;
				
			lastString = stringFromOp(lastOp);
			string = stringFromOp(op);
				
			if (lastString && string) {
				[operations removeObjectAtIndex: opPos];
				[self putString: [lastString stringByAppendingString: string]
						toStream: stream];
				return;
			}
		} else if (lastOp &&
				   [lastOp selector] == @selector(putData:toStream:) &&
				   [op selector] == @selector(putData:toStream:) &&
				   stream == lastStream) {
			// Data writes can also be concatenated
			NSData* oldData = nil;
			[lastOp getArgument: &oldData
						atIndex: 2];
			
			NSData* nextData = nil;
			[op getArgument: &nextData
					atIndex: 2];
			
			NSMutableData* newData = nil;
			if ([oldData isKindOfClass: [NSMutableData class]]) {
				newData = (NSMutableData*)oldData;
			} else {
				newData = [[oldData mutableCopy] autorelease];
			}
			
			if (newData && nextData) {
				[newData appendData: nextData];
				[operations removeObjectAtIndex: opPos];
				[self putData: newData
					 toStream: stream];
				return;
			}
		}
	}
	
	[op retainArguments];
	[operations addObject: op];
}

- (BOOL) shouldBeFlushed {
	return [operations count]>0;
}

- (BOOL) hasGotABitOnTheLargeSide {
	return [operations count] > GlkBigBuffer;
}

- (void) flushToTarget: (id) target {
	NSEnumerator* bufferEnum = [operations objectEnumerator];
	NSInvocation* op;
	
	while (op = [bufferEnum nextObject]) {
		if ([op target] == nil) [op setTarget: self];
		[op invokeWithTarget: target];
	}
}

// = NSCoding =

- (id) initWithCoder: (NSCoder*) coder {
	self = [super init];
	
	if (self) {
		operations = [[NSMutableArray alloc] initWithArray: [coder decodeObject]
												 copyItems: NO];
	}
	
	return self;
}

- (void) encodeWithCoder: (NSCoder*) coder {
	[coder encodeObject: operations];
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)encoder {
	// This ensures that when we're passed in a bycopy way, we get passed as an actual copy and not a NSDistantObject
	// (which would kind of defeat the whole purpose of the buffer in the first place)
    
	// GYAHRGH, Lion is a piece of crap. Prior to this version of OS X, this could handle object graphs. Now it just crashes.
	// If I ungraph the thing then it just seems to do nothing, and it's impossible to debug because it's refusing to set breakpoints anywhere useful.
	// if ([encoder isBycopy]) return self;
    return [super replacementObjectForPortCoder:encoder];	
}

// = NSCopying =

- (id) copyWithZone: (NSZone*) zone {
	GlkBuffer* copy = [[GlkBuffer allocWithZone: zone] init];
	
	[copy->operations release];
	copy->operations = [[NSMutableArray alloc] initWithArray: operations
												   copyItems: YES];
	
	return copy;
}

// = Forwarding invocations =

// Anything not specifically supported by the buffer is stored as an operation

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
	// If aSelector exists in the GlkBuffer protocol, then we use that signature
	return [super methodSignatureForSelector: aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
	[self addOperation: anInvocation];
}

// Warnings. Lots of warnings. These are deliberate, so don't panic. Too much.

@end
