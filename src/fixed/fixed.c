#include "fixed.h"


uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;
    while (b) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        ++*n;
    }
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a >> 1) + (b >> 1) + (a & b & 1);
}


static uint64_t umul32(uint32_t x, uint32_t y)
{
    uint32_t x_h, x_l, y_h, y_l;
    uint64_t sum;
    uint32_t ll, hh, lh, hl;
    x_h = x >> 16;
    x_l = x & 0xffff;
    y_h = y >> 16;
    y_l = y & 0xffff;
    hh = (x_h * y_h);
    hl = (x_h * y_l);
    lh = (y_h * x_l);
    ll = x_l * y_l;

    sum = ((uint64_t) hh << 32) + (((uint64_t) hl + lh) << 16) + ll;
    return sum;
}


int32_t q_mul(int32_t a, int32_t b)
{
    uint64_t mul;
    uint32_t ua, ub;
    if (a < 0) {
        ua = 0u - a;
    } else {
        ua = a;
    }
    if (b < 0) {
        ub = 0u - b;
    } else {
        ub = b;
    }
    mul = umul32(ua, ub);
    if ((a < 0) != (b < 0)) {
        mul = 0u - mul;
    }
    return (int32_t) ((mul + (1u << 19)) >> 20);
}
