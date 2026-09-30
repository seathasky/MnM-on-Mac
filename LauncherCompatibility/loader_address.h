#include <stdint.h>
/* Resolve an exported function's RVA against the target's module mapping. */
static uintptr_t relocated_loader(uintptr_t local_function,uintptr_t local_base,
                                  uintptr_t target_base,uintptr_t target_size) {
    if(!local_function || !local_base || !target_base || local_function<local_base)return 0;
    uintptr_t offset=local_function-local_base;
    if(offset>=target_size || target_base>UINTPTR_MAX-offset)return 0;
    return target_base+offset;
}
