#include <assert.h>
#include <stdio.h>
#include "controller_lease.h"
#define SECONDS(n) ((unsigned long long)(n)*10000000ULL)
int main(void) {
    unsigned long long base=SECONDS(1000000);
    assert(!controller_lease_expired(base+SECONDS(1),base));
    assert(!controller_lease_expired(base+SECONDS(25),base));
    assert(!controller_lease_expired(base+SECONDS(59),base));
    assert(controller_lease_expired(base+SECONDS(61),base));
    assert(!controller_lease_expired(base,base+SECONDS(120)));
    puts("Heartbeat policy tests passed (fresh, throttled, gone, clock skew).");
}
