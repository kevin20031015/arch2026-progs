# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    lui t1, 0x7f800
    and t0, a0, t1
    beq t0, t1, f32done
    srli t0, a0, 16
    andi t0, t0, 1
    add a0, a0, t0
    lui t1, 0x8
    addi t1, t1, -1
    add a0, a0, t1
    f32done:
    srli a0, a0, 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2

# 暫存器	放什麼
# a0	a
# a1	b
# t0	result_sign
# t1	exp_a
# t2	mant_a
# t3	exp_b
# t4	mant_b
# t6	常數 0xFF

bf16_mul_asm:
    xor t0, a0, a1
    srli t0, t0, 15
    slli t0, t0, 15
    srli t1, a0, 7
    andi t1, t1, 0xff
    andi t2, a0, 0x7f 
    srli t3, a1, 7
    andi t3, t3, 0xff
    andi t4, a1, 0x7f 
    li t6, 0xff

    bne t1, t6, mulcheckb
    bnez t2, mulret
    or t5, t3, t4
    beqz t5, mulnan
    j mulinf

    mulcheckb:
        bne t3, t6, mulseg3
        bnez t4, mulretb
        or t5, t1, t2
        beqz t5, mulnan
        j mulinf

    mulseg3:
        or t5, t1, t2
        beqz t5, mul0
        or t5, t3, t4
        beqz t5, mul0
        li a2, 0 #exp_adjust
        bnez t1, mulhida
        mulnorma:
            slli t2, t2, 1
            addi a2, a2, -1
            andi t5, t2, 0x80
            beqz t5, mulnorma

        li t1, 1

    j mulb 

    mulhida:
        ori t2, t2, 0x80
    
    mulb:
        bnez t3, mulhidb
        mulnormb:
            slli t4, t4, 1
            addi a2, a2, -1
            andi t5, t4, 0x80
            beqz t5, mulnormb

        li t3, 1
    j mulseg4

    mulhidb:
        ori t4, t4, 0x80

# a3 = result_mant，a4 = result_exp

    mulseg4:
        li a3, 0

    mulloop:
        andi t5, t4, 1
        beqz t5, mulskip
        add a3, a3, t2
    
    mulskip:
        slli t2, t2, 1
        srli t4, t4, 1
        bnez t4, mulloop
    
    add a4, t1, t3
    addi a4, a4, -127
    add a4, a4, a2
    srli t5, a3, 15
    beqz t5, mulsh7
    srli a3, a3, 8
    addi a4, a4, 1
    j mulmask
    mulsh7:
        srli a3, a3, 7
    mulmask:
        andi a3, a3, 0x7f
    
    mulseg5:
        bge a4, t6, mulinf
        bgtz a4, mulpack
        li t5, -6
        blt a4, t5, mul0
        li t5, 1
        sub t5, t5, a4
        srl a3, a3, t5
        li a4, 0
    
    mulpack:
        slli a4, a4, 7
        or a0, t0, a4
        or a0, a0, a3
    


    ret

    mulretb:
        mv a0, a1
        ret

    mulnan:

        lui  a0, 0x8
        addi a0, a0, -64
        ret

    mulinf:
        lui  t5, 0x8
        addi t5, t5, -128
        or a0, t0, t5
        ret

    mul0:
        mv a0, t0
        ret

    mulret:
        ret

    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2

#  暫存器	放什麼
#  a0	a
#  t0	sign
#  t1	exp
#  t2	mant
#  t6	常數 0xFF  

bf16_sqrt_asm:
    srli t0, a0, 15
    srli t1, a0, 7
    andi t1, t1, 0xff
    andi t2, a0, 0x7f
    li t6, 0xff
    bne t1, t6, sqnotff
    bnez t2, sqret
    bnez t0, sqnan
    ret

    sqnotff:
        bnez t1, sqnormal
        beqz t2, sq0
        bnez t0, sqnan
        j sq0

    sqnormal:
        bnez t0, sqnan
# t3 = e、t4 = m、t5 = new_exp
    sqseg2:
        addi t3, t1, -127
        or t4, t2, 0x80
        andi t0, t3, 1
        beqz t0, sqeven
        slli t4, t4, 1
        addi t3, t3, -1

        sqeven:
            srai t5, t3, 1 # e might minus
            addi t5, t5, 127
        
# 暫存器	放什麼
# a1	low
# a2	high
# a3	result
# a4	mid
# a5	mid × mid（之後變成 sq）
# a6	mid 的copy
# a7	mid 的copy
# t0	暫存

    
    sqseg3:
        li a1, 90
        li a2, 256
        li a3, 128
    
    sqloop:
        add a4, a1, a2
        srli a4, a4, 1
        li a5, 0
        mv a6, a4
        mv a7, a4

    sqmulloop:
        andi t0, a7, 1
        beqz t0, sqmulskip
        add a5, a5, a6

    sqmulskip:
        slli a6, a6, 1
        srli a7, a7, 1
        bnez a7, sqmulloop
        srli a5, a5, 7
        bgtu a5, t4, sqtoobig
        mv a3, a4
        addi a1, a4, 1
        j sqcheck

    sqtoobig:
        addi a2, a4, -1

    sqcheck:
        bleu a1, a2, sqloop

    sqseg4:
        slli t5, t5, 7
        andi a3, a3, 0x7f
        or a0, t5, a3
    ret

    sq0:
        li a0, 0
        ret
    
    sqnan:
        lui a0, 0x8
        addi a0, a0, -64
        ret

    sqret:
        ret



    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
