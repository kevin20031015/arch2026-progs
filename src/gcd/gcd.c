#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0) {
        return b;
    }
    if (b == 0) {
        return a;
    }
    int k;
    k = 0;
    while (((a & 1) == 0) && ((b & 1) == 0)) {
        a = a >> 1;
        b = b >> 1;
        k = k + 1;
    }
    while (((a & 1) == 0)) {
        a = a >> 1;
    }
    while (b != 0) {
        while (((b & 1) == 0)) {
            b = b >> 1;
        }

        if (a > b) {
            uint32_t q;
            q = b;
            b = a;
            a = q;
        }
        b = b - a;
    }
    return a << k;
}
