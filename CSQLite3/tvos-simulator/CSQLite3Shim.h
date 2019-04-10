#ifndef __CSQLITE3_SHIM_H__
#define __CSQLITE3_SHIM_H__

#if defined(__APPLE__) && defined(__MACH__)
#  if __clang_major__ >= 11 // Assume Xcode-beta.app (XcodeXbeta)
#    include "/Applications/Xcode-beta.app/Contents/Developer/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator.sdk/usr/include/sqlite3.h"
#  else
#    include "/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator.sdk/usr/include/sqlite3.h"
#  endif
#else
#  include "/usr/include/sqlite3.h"
#endif

#endif /* __CSQLITE3_SHIM_H__ */
