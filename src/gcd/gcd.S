# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2

gcd_u32_asm:
    beq     a0, x0, pa_alt       # a0 is zero: the answer is in a1
    beq     a1, x0, pa_end        # a1 is zero: a0 already holds it
    addi    t0, x0, 0       # count of shared twos, starting here
pa_both:
    or t1, a0, a1            # combine a and b
    andi    t1, t1, 1       # keep the parity bit
    bne     t1, x0, pa_left
    srli    a0, a0, 1             # a /= 2, with no sign to preserve
    srli    a1, a1, 1             # b /= 2
    addi    t0, t0, 1       # one more shared two
    jal     x0, pa_both           # back to the head of this loop
pa_left:
    andi    t1, a0, 1
    bne     t1, x0, pa_right     # a is odd now, go work on b
    srli    a0, a0, 1
    jal     x0, pa_left
pa_right:
    andi    t1, a1, 1
    bne     t1, x0, pa_order

pa_right_shift:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, x0, pa_right_shift
pa_order:
    bgeu    a1, a0, pa_step       # skip the swap while b >= a holds
    addi    t2, a0, 0             # swap a and b
    addi    a0, a1, 0
    addi    a1, t2, 0
pa_step:
    sub     a1, a1, a0            # b -= a, and b stays even
    bne     a1, x0, pa_right_shift     # b is not zero yet
    sll a0, a0, t0            # put the shared twos back
    jalr    x0, ra, 0
pa_alt:
    addi    a0, a1, 0
pa_end:
    jalr    x0, ra, 0
    .size   gcd_u32_asm, .-gcd_u32_asm
