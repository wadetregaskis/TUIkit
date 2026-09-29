//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CTestSupport.h
//
//  Shapes a test needs that only the C importer makes: Swift cannot declare
//  them, and a system header's are not the same on every platform the suite
//  runs on.
//
//  Created by Wade Tregaskis
//  License: MIT

#ifndef CTESTSUPPORT_H
#define CTESTSUPPORT_H

/// A byte, a byte holding two 4-bit bitfields, then an int. The runtime's
/// field list for the imported struct names `c` (offset 0) and `x` (offset 4)
/// and leaves the bitfields out, so their byte, at offset 1, lies in a gap
/// shaped exactly like `x`'s alignment padding.
struct CTestBitfields {
    unsigned char c;
    unsigned char lo : 4;
    unsigned char hi : 4;
    int x;
};

/// A byte, then an int: a gap at 1..<4 that IS alignment padding, in a struct
/// whose field list the importer wrote.
struct CTestPadded {
    unsigned char c;
    int x;
};

#endif
