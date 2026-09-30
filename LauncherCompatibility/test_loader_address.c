#include <assert.h>
#include <stdio.h>
#include "loader_address.h"
int main(void) {
    assert(relocated_loader(0x10001234,0x10000000,0x10000000,0x20000)==0x10001234);
    /* The rendering process maps the DLL elsewhere: do not reuse the helper address. */
    assert(relocated_loader(0x10001234,0x10000000,0x78000000,0x20000)==0x78001234);
    assert(relocated_loader(0x10001234,0x10000000,0x78000000,0x1234)==0);
    assert(relocated_loader(0x10001234,0x20000000,0x78000000,0x20000)==0);
    assert(relocated_loader(0x10001234,0x10000000,0,0x20000)==0);
    assert(relocated_loader(0x10001234,0x10000000,UINTPTR_MAX-100,0x20000)==0);
    puts("Loader relocation tests passed (same mapping, different mapping, invalid bounds).");
}
