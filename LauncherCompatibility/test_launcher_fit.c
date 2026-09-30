#include <assert.h>
#include <stdio.h>
#include "launcher_fit.h"
int main(void) {
    /* A 1280x800-point Retina screen, excluding menu bar and Dock. */
    assert(launcher_fit_percent(0,1940,1400,176,2560,1460,6,57,40)==86);
    /* The same logical screen at 1x gives the same default scale. */
    assert(launcher_fit_percent(0,970,700,88,1280,730,3,29,20)==86);
    /* DPI-unaware Wine on a Retina display still uses 96-DPI coordinates.
     * Never substitute the display's 2x backing ratio for this window DPI. */
    int unaware=launcher_fit_percent(0,970,700,88,1920,1080,3,29,20);
    assert(unaware==100);
    assert(970*unaware/100==970);
    assert(788*unaware/100==788);
    /* Changing macOS resolution must recalculate fit, not retain the old size. */
    int small=launcher_fit_percent(125,970,700,88,1280,650,3,29,20);
    assert(small==76);
    assert(788*small/100+29+20<=650);
    assert(launcher_fit_percent(125,970,700,88,1920,1080,3,29,20)==125);
    assert(launcher_fit_percent(0,970,700,88,1280,650,3,29,20)==76);
    assert(launcher_fit_percent(0,970,700,88,1920,1080,3,29,20)==100);
    /* Small work areas cap even a saved manual zoom. */
    int fit=launcher_fit_percent(125,1940,1400,176,2560,1460,6,57,40);
    assert(fit==86);
    assert(1940*fit/100+6<=2560-40);
    assert(1576*fit/100+57<=1460-40);
    assert(launcher_fit_percent(60,1940,1400,176,3840,1988,6,57,40)==60);
    assert(launcher_fit_percent(125,1940,1400,176,3840,1988,6,57,40)==119);
    /* A prior window size cannot compound: it is not an input. */
    for(int launch=0;launch<10;launch++)
        assert(launcher_fit_percent(0,1940,1400,176,2560,1460,6,57,40)==86);
    puts("Launcher fit tests passed (1x, Retina, small screens, manual zoom, reopen).");
}
