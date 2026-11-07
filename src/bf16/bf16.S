# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

# bf16_from_f32_asm: narrow a binary32 pattern to bf16.
#   a0: f32bits, then the result   t0: exponent field, then bit 16
#   t1: exponent mask 0x7F800000, then 0x7FFF
    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    lui     t1, 0x7f800
    and     t0, a0, t1
    beq     t0, t1, f32done         # Inf or NaN: no rounding
# Round to nearest even: add 0x7FFF plus bit 16. A tie carries into
# the kept half when bit 16 is 1 and is dropped when it is 0.
    srli    t0, a0, 16
    andi    t0, t0, 1
    add     a0, a0, t0
    lui     t1, 0x8
    addi    t1, t1, -1
    add     a0, a0, t1
f32done:
    srli    a0, a0, 16              # both paths keep the top 16 bits
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

# bf16_mul_asm: bf16 product, the fraction truncated.
#   a0: a, then the result   a1: b   t0: result sign, kept at bit 15
#   t1, t2: exponent and fraction of a   t3, t4: exponent and fraction of b
#   t5: scratch   t6: the constant 0xFF
#   a2: exp_adjust   a3: result_mant   a4: result_exp
    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
# The sign stays at bit 15, where every return needs it, which saves a
# shift on each of them.
    xor     t0, a0, a1
    srli    t0, t0, 15
    slli    t0, t0, 15
    srli    t1, a0, 7
    andi    t1, t1, 0xff
    andi    t2, a0, 0x7f
    srli    t3, a1, 7
    andi    t3, t3, 0xff
    andi    t4, a1, 0x7f
    li      t6, 0xff

# Inf and NaN: a is examined completely before b, as the contract
# requires (Inf times a NaN b is Inf).
    bne     t1, t6, mulcheckb
    bnez    t2, mulret
    or      t5, t3, t4
    beqz    t5, mulnan
    j       mulinf

mulcheckb:
    bne     t3, t6, mulseg3
    bnez    t4, mulretb
    or      t5, t1, t2
    beqz    t5, mulnan
    j       mulinf

# A value is zero when its exponent and fraction are both zero; the
# product is then a zero with the product sign. Otherwise make each
# significand 1.xxxxxxx: add the hidden 1, or shift a denormal left
# until bit 7 is set, lowering the exponent once per shift.
mulseg3:
    or      t5, t1, t2
    beqz    t5, mul0
    or      t5, t3, t4
    beqz    t5, mul0
    li      a2, 0
    bnez    t1, mulhida
mulnorma:
    slli    t2, t2, 1
    addi    a2, a2, -1
    andi    t5, t2, 0x80
    beqz    t5, mulnorma

    li      t1, 1

    j       mulb

mulhida:
    ori     t2, t2, 0x80

mulb:
    bnez    t3, mulhidb
mulnormb:
    slli    t4, t4, 1
    addi    a2, a2, -1
    andi    t5, t4, 0x80
    beqz    t5, mulnormb

    li      t3, 1
    j       mulseg4

mulhidb:
    ori     t4, t4, 0x80

# 8-bit by 8-bit shift-and-add. The multiplier has 8 bits with bit 7
# set, so the loop runs exactly 8 times.
mulseg4:
    li      a3, 0

mulloop:
    andi    t5, t4, 1
    beqz    t5, mulskip
    add     a3, a3, t2

mulskip:
    slli    t2, t2, 1
    srli    t4, t4, 1
    bnez    t4, mulloop

# Each exponent carries a bias of 127, so the sum has one too many. A
# product with bit 15 set is 2.0 or more: shift one bit further and
# carry it into the exponent.
    add     a4, t1, t3
    addi    a4, a4, -127
    add     a4, a4, a2
    srli    t5, a3, 15
    beqz    t5, mulsh7
    srli    a3, a3, 8
    addi    a4, a4, 1
    j       mulmask
mulsh7:
    srli    a3, a3, 7
mulmask:
    andi    a3, a3, 0x7f

# Exponent too large: Inf. Too small (below -6): zero. From -6 to 0:
# a denormal, the fraction shifted right by 1 - exponent. The exponent
# may be negative, so the comparisons are signed.
mulseg5:
    bge     a4, t6, mulinf
    bgtz    a4, mulpack
    li      t5, -6
    blt     a4, t5, mul0
    li      t5, 1
    sub     t5, t5, a4
    srl     a3, a3, t5
    li      a4, 0

mulpack:
    slli    a4, a4, 7
    or      a0, t0, a4
    or      a0, a0, a3

    ret

mulretb:
    mv      a0, a1
    ret

mulnan:
    lui     a0, 0x8
    addi    a0, a0, -64
    ret

mulinf:
    lui     t5, 0x8
    addi    t5, t5, -128
    or      a0, t0, t5
    ret

mul0:
    mv      a0, t0
    ret

mulret:
    ret

    .size   bf16_mul_asm, .-bf16_mul_asm

# bf16_sqrt_asm: bf16 square root by the binary search of the C version.
#   a0: a, then the result   t0: sign (0 or 1), then scratch
#   t1: exponent field   t2: fraction field   t6: the constant 0xFF
#   t3: e = exponent - 127   t4: m, the scaled significand   t5: new_exp
#   a1: low   a2: high   a3: result   a4: mid
#   a5: mid * mid, then divided by 128   a6, a7: copies of mid to multiply
    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
# Special values, grouped by the exponent field: 0xFF (NaN, Inf), 0
# (zeros, denormals) and the rest (negative values). This takes fewer
# branches than checking the cases one by one as the C version does.
    srli    t0, a0, 15
    srli    t1, a0, 7
    andi    t1, t1, 0xff
    andi    t2, a0, 0x7f
    li      t6, 0xff
    bne     t1, t6, sqnotff
    bnez    t2, sqret
    bnez    t0, sqnan
    ret

sqnotff:
    bnez    t1, sqnormal
    beqz    t2, sq0
    bnez    t0, sqnan
    j       sq0

sqnormal:
    bnez    t0, sqnan
# sqrt(2^e * m) = 2^(e/2) * sqrt(m) needs an even e: for an odd e,
# double m and lower e by one. e may be negative, so halve it with an
# arithmetic shift.
sqseg2:
    addi    t3, t1, -127
    ori     t4, t2, 0x80
    andi    t0, t3, 1
    beqz    t0, sqeven
    slli    t4, t4, 1
    addi    t3, t3, -1

sqeven:
    srai    t5, t3, 1
    addi    t5, t5, 127

# Binary search for the largest mid in [90, 256] with
# mid * mid / 128 <= m: that mid is the significand of the root.
sqseg3:
    li      a1, 90
    li      a2, 256
    li      a3, 128

sqloop:
    add     a4, a1, a2
    srli    a4, a4, 1
    li      a5, 0
    mv      a6, a4                  # the shifts destroy both operands,
    mv      a7, a4                  # and mid is still needed afterwards

sqmulloop:
    andi    t0, a7, 1
    beqz    t0, sqmulskip
    add     a5, a5, a6

sqmulskip:
    slli    a6, a6, 1
    srli    a7, a7, 1
    bnez    a7, sqmulloop
    srli    a5, a5, 7
    bgtu    a5, t4, sqtoobig
    mv      a3, a4
    addi    a1, a4, 1
    j       sqcheck

sqtoobig:
    addi    a2, a4, -1

sqcheck:
    bleu    a1, a2, sqloop

# No renormalization or exponent check, unlike the C version: they can
# never fire. m is in [128, 510], so the result is in [128, 255]
# (128 * 128 / 128 = 128 <= m, and 256 * 256 / 128 = 512 > m), and with
# e in [-126, 127] the new exponent is in [64, 190].
sqseg4:
    slli    t5, t5, 7
    andi    a3, a3, 0x7f
    or      a0, t5, a3
    ret

sq0:
    li      a0, 0
    ret

sqnan:
    lui     a0, 0x8
    addi    a0, a0, -64
    ret

sqret:
    ret

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
