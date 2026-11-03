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

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    addi t0, x0, 0
    beq a1, x0, op1_end
    op1_loop:
    and t1, a0, a1
    xor a0, a0, a1
    slli a1, t1, 1
    addi t0, t0, 1
    bne a1, x0, op1_loop

    op1_end:
    sw t0, 0(a2)

    ret
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    xor t0, a0, a1
    and t1, a0, a1
    srli t0, t0, 1
    add a0, t0, t1
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    xor t0, a0, a1
    bge a0, x0, absa
    sub a0, x0, a0
    absa:
    bge a1, x0, absb
    sub a1, x0, a1
    absb:
    li a2, 0
    li a3, 0
    li a4, 0
    loop:
    andi t1, a1, 1
    beqz t1, skip
    add a2, a2, a0
    sltu t2, a2, a0
    add a3, a3, a4
    add a3, a3, t2

    skip:
    srli t3, a0, 31
    slli a4, a4, 1
    or a4, a4, t3
    slli a0, a0, 1
    srli a1, a1, 1
    bne a1, x0, loop

# 	          高 32 位元	低 32 位元
#被乘數（a）	a4	         a0
#乘積	        a3	         a2
#乘數（b）	    —	         a1
    bgez t0, eq
    sub a2, x0, a2
    sub a3, x0, a3
    beq a2, x0, zee
    addi a3, a3, -1
    zee:

    eq:
    lui t6, 0x80
    add a2, a2, t6
    sltu t5, a2, t6
    add a3, a3, t5
    srli a2, a2, 20
    slli a3, a3, 12
    or a0, a2, a3 

    ret
    .size   q_mul_asm, .-q_mul_asm
