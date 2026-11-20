#ifndef MNM_CONTROLLER_LEASE_H
#define MNM_CONTROLLER_LEASE_H

static inline int controller_lease_expired(unsigned long long current, unsigned long long renewed) {
    const unsigned long long lease_duration = 60ULL * 10000000ULL;
    if (current <= renewed) return 0;
    return current - renewed > lease_duration;
}

#endif
