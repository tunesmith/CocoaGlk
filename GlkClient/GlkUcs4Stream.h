//
//  GlkUcs4Stream.h
//  CocoaGlk
//
//  Created by Andrew Hunter on 19/08/2006.
//  Copyright 2006 Andrew Hunter. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import <GlkClient/GlkStreamProtocol.h>

///
/// Conversion stream that turns standard GlkStream objects into UCS-4 ones
///
@interface GlkUcs4Stream : NSObject<GlkStream> {
	NSObject<GlkStream>* dataStream;								// The stream that gets the results of writing to this stream
	BOOL bigEndian;													// YES if the stream should be written in a big-endian manner
}

- (id) initWithStream: (NSObject<GlkStream>*) dataStream
			bigEndian: (BOOL) bigEndian;

@end
