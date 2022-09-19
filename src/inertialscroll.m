#include "Cocoa/Cocoa.h"

void enable_inertial_scroll(void) {
    [[NSUserDefaults standardUserDefaults] setBool: YES
        forKey: @"AppleMomentumScrollSupported"];
}