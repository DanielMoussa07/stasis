// Copyright (C) 2026 Daniel Moussa
// Part of Stasis, licensed under the GNU General Public License v3.0 (see LICENSE).
//
// Declarations for the few undocumented IOKit power-management calls Stasis uses.
// They are exported by IOKit.framework but absent from the public SDK headers.

#ifndef IOPMLibPrivate_h
#define IOPMLibPrivate_h

#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// System-wide setting that stops the Mac from sleeping (value is a CFBoolean).
#define kIOPMSleepDisabledKey CFSTR("SleepDisabled")

// Returns the system-wide power settings; the caller releases the result.
CFDictionaryRef IOPMCopySystemPowerSettings(void);

// Sets one system-wide power setting and returns kIOReturnSuccess on success.
IOReturn IOPMSetSystemPowerSetting(CFStringRef key, CFTypeRef value);

#ifdef __cplusplus
}
#endif

#endif
