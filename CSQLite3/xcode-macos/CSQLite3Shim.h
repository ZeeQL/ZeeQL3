#ifndef __CSQLITE3_SHIM_H__
#define __CSQLITE3_SHIM_H__

#if defined(__APPLE__) && defined(__MACH__)
// TODO: this may have issues with LLDB as outlined below
#  if __clang_major__ >= 10 // Assume Xcode-beta.app (XcodeXbeta)
#    include "/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sqlite3.h"
#  else __clang_major__ >= 9
#    include "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sqlite3.h"
#endif
/* doesn't work well with LLDB, but we just want 9 now anyways
#  if __clang_major__ >= 9 // released now. assume Xcode 9.
#    include "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sqlite3.h"
#  else
#    include "/Applications/Xcode 8.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sqlite3.h"
#  endif
 */
#else
#  include "/usr/include/sqlite3.h"
#endif

#endif /* __CSQLITE3_SHIM_H__ */
