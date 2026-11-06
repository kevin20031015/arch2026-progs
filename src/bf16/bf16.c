#include "bf16.h"


uint16_t bf16_from_f32(uint32_t f32bits)
{
    if (((f32bits >> 23) & 0xFF) == 0xFF)
        return (uint16_t) ((f32bits >> 16) & 0xFFFF);

    f32bits += ((f32bits >> 16) & 1) + 0x7FFF;
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign_a, sign_b, result_sign;
    int32_t exp_a, exp_b;
    uint32_t mant_a, mant_b;
    int32_t exp_adjust = 0;
    uint32_t result_mant;
    int32_t result_exp;
    sign_a = (a >> 15) & 1;
    exp_a = (a >> 7) & 0xff;
    mant_a = a & 0x7f;
    sign_b = (b >> 15) & 1;
    exp_b = (b >> 7) & 0xff;
    mant_b = b & 0x7f;
    result_sign = sign_a ^ sign_b;

    if (exp_a == 0xff) {
        if (mant_a != 0) {
            return a;
        } else if ((exp_b == 0) && (mant_b == 0)) {
            return 0x7fc0;
        } else {
            return (result_sign << 15) | 0x7f80;
        }
    }

    if (exp_b == 0xff) {
        if (mant_b != 0) {
            return b;
        } else if ((exp_a == 0) && (mant_a == 0)) {
            return 0x7fc0;
        } else {
            return (result_sign << 15) | 0x7f80;  // 回傳帶正負號的無限大
        }
    }

    if (((exp_a == 0) && (mant_a == 0)) || ((exp_b == 0) && (mant_b == 0))) {
        return (result_sign << 15);  // 回傳帶正負號的 0
    }

    if (exp_a != 0) {
        mant_a = mant_a | 0x80;
    } else {
        while ((mant_a & 0x80) == 0) {
            mant_a = mant_a << 1;
            exp_adjust -= 1;
        }
        exp_a = 1;
    }

    if (exp_b != 0) {
        mant_b = mant_b | 0x80;
    } else {
        while ((mant_b & 0x80) == 0) {
            mant_b = mant_b << 1;
            exp_adjust -= 1;
        }
        exp_b = 1;
    }

    result_mant = mant_a * mant_b;
    result_exp = exp_a + exp_b - 127 + exp_adjust;
    if ((result_mant & 0x8000) != 0) {
        result_mant = result_mant >> 8;
        result_exp += 1;
    } else {
        result_mant = result_mant >> 7;
    }

    result_mant = result_mant & 0x7f;

    if (result_exp >= 0xff) {
        return (result_sign << 15) | 0x7f80;
    }

    if (result_exp <= 0) {
        if (result_exp < -6) {
            return (result_sign << 15);
        } else {
            result_mant = result_mant >> (1 - result_exp);
            result_exp = 0;
        }
    }



    return (result_sign << 15) | (result_exp << 7) | (result_mant);
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t sign, mant;
    int32_t exp;
    int32_t e, new_exp;
    uint32_t m;
    sign = (a >> 15) & 1;
    exp = (a >> 7) & 0xff;
    mant = a & 0x7f;
    if (exp == 0xff) {
        if (mant != 0) {
            return a;
        }
    }

    if ((exp == 0) && (mant == 0)) {
        return 0x0000;
    }

    if (sign == 1) {
        return 0x7fc0;
    }

    if (exp == 0xff) {
        return a;
    }

    if (exp == 0) {
        return 0x0000;
    }

    e = exp - 127;
    m = mant | 0x80;

    if (e & 1) {
        m <<= 1;
        new_exp = ((e - 1) >> 1) + 127;
    } else {
        new_exp = (e >> 1) + 127;
    }

    uint32_t low = 90, high = 256, result = 128;

    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        uint32_t sq = (mid * mid) / 128;

        if (sq <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    if (result >= 256) {
        result = result >> 1;
        new_exp += 1;
    }

    if (result < 128) {
        result = result << 1;
        new_exp -= 1;
    }

    if (new_exp >= 0xff) {
        return 0x7f80;
    }

    if (new_exp <= 0) {
        return 0x0000;
    }


    return (new_exp << 7) | (result & 0x7f);
}
