# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

# op1_asm: a + b with logic only.
#   a0: a, then the sum (returned)   a1: b, then the carry word
#   a2: n (pointer)   t0: pass count   t1: a & b before the shift
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    addi    t0, x0, 0
    beq     a1, x0, op1_end         # b is zero: no pass at all
# Add without '+': a ^ b is the sum without carries, (a & b) << 1 is
# the carry. Repeat until the carry is zero, counting the passes in t0.
op1_loop:
    and     t1, a0, a1
    xor     a0, a0, a1
    slli    a1, t1, 1
    addi    t0, t0, 1
    bne     a1, x0, op1_loop

op1_end:
    sw      t0, 0(a2)

    ret
    .size   op1_asm, .-op1_asm

# op2_asm: a - b.   a0: a, then the result   a1: b
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

# op3_asm: floor((a + b) / 2) without overflow.
#   a0: a, then the result   a1: b   t0: a ^ b   t1: a & b
# floor((a + b) / 2) = (a & b) + ((a ^ b) >> 1): the carries and the
# carry-free sum are kept apart, and their sum is the result itself,
# so it never needs a 33rd bit.
    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    xor     t0, a0, a1
    and     t1, a0, a1
    srli    t0, t0, 1
    add     a0, t0, t1
    ret
    .size   op3_asm, .-op3_asm

# q_mul_asm: Q11.20 product, rounded by adding 2^19.
#   a0, a4: |a|, low and high words of the multiplicand (shifted left)
#   a1: |b|, the multiplier (shifted right)
#   a2, a3: low and high words of the 64-bit product; a0 returns the result
#   t0: sign, bit 31 set when the signs differ   t1: low bit of the multiplier
#   t2: carry out of the low-word add   t3: top bit of a0, moving into a4
#   t5: carry out of the rounding add   t6: 2^19, the rounding constant
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    xor     t0, a0, a1              # bit 31 set: the signs differ
    bge     a0, x0, absa
    sub     a0, x0, a0
absa:
    bge     a1, x0, absb
    sub     a1, x0, a1
absb:
    li      a2, 0
    li      a3, 0
    li      a4, 0
# Shift-and-add: when the low bit of the multiplier is 1, add the
# multiplicand to the product; then shift the multiplicand left and
# the multiplier right, until the multiplier is zero.
loop:
    andi    t1, a1, 1
    beqz    t1, skip
    add     a2, a2, a0
    sltu    t2, a2, a0              # smaller than what was added: carry
    add     a3, a3, a4
    add     a3, a3, t2

# Shift the 64-bit multiplicand left by 1: the top bit of the low
# word moves up into the bottom of the high word (saved first).
skip:
    srli    t3, a0, 31
    slli    a4, a4, 1
    or      a4, a4, t3
    slli    a0, a0, 1
    srli    a1, a1, 1
    bne     a1, x0, loop

# Signs differ: negate the 64-bit product. The low word borrows from
# the high word unless it is zero, so the high word drops one more.
# This comes before the rounding, so ties still round toward +inf.
    bgez    t0, eq
    sub     a2, x0, a2
    sub     a3, x0, a3
    beq     a2, x0, zee
    addi    a3, a3, -1
zee:
# The shift right by 20 drops 2^20 per output unit; adding half of
# that, 2^19, first makes it round to nearest, ties toward +inf. The
# result is bits 20..51 of that sum: the top 12 bits of the low word
# and the low 20 bits of the high word, shifted back into place.
eq:
    lui     t6, 0x80                # t6 = 0x80000 = 2^19
    add     a2, a2, t6
    sltu    t5, a2, t6
    add     a3, a3, t5
    srli    a2, a2, 20
    slli    a3, a3, 12
    or      a0, a2, a3

    ret
    .size   q_mul_asm, .-q_mul_asm
