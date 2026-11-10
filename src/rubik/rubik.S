# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#   a0 = state, a1 = out, a2 = cap; result in a0
#
# Search the first part of the answer, then finish it with the table of
# every state within five moves of the solved cube (tables_asm.S, the same
# numbers as tables.c). A state at distance d joins the table at depth
# max(0, d - 5), so bounds 0 to 6 cover every distance up to 11.
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.

    .data
# The factorials for ranking the permutation.
fact:
    .word   720, 120, 24, 6, 2, 1, 1
# The 14 input digits, '1' to '7' turned into 0 to 6.
state:
    .zero   14
# Marks for the permutation check.
seen:
    .zero   7
# The face (0 = R, 1 = B, 2 = D) and the quarter turns of each move.
# Face 3 belongs to last = 9, which means no previous move.
move_face:
    .byte   0, 0, 0, 1, 1, 1, 2, 2, 2, 3
move_turns:
    .byte   1, 2, 3, 1, 2, 3, 1, 2, 3
# The moves of the answer, at most 11.
solution:
    .zero   11
# Two bytes per name; a second byte of 0 means there is no second
# character.
move_names:
    .byte   82, 0, 82, 50, 82, 39       # R, R2, R'
    .byte   66, 0, 66, 50, 66, 39       # B, B2, B'
    .byte   68, 0, 68, 50, 68, 39       # D, D2, D'
# The search stack: 16 bytes per level holding p, o, next and last at
# offsets 0, 4, 8 and 12. Seven levels (depth 0 to 6) take 112 bytes.
    .align  2
frames:
    .zero   112

    .text

# Registers during the search:
#   s0, s3: p and o of the input        s1: index found in the table
#   s2: the constant 9                  s4: address of the current frame
#   s5: bound                           s6: depth
#   s7: move_face
#   s8, s10: p_move_rows_asm, o_move_rows_asm
#   s9, s11: group_start_asm, group_orientation_asm
#   a1, a2: out and cap, kept for writing the answer
# Once the answer is found, s0 and s3 hold the current state and s5 the
# length of the answer.
    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
# s0-s11 must be restored before returning, so save them, and ra, the
# return address. The 13 words take 52 bytes; 64 keeps sp 16-byte
# aligned.
    addi    sp, sp, -64
    sw      ra, 0(sp)
    sw      s0, 4(sp)
    sw      s1, 8(sp)
    sw      s2, 12(sp)
    sw      s3, 16(sp)
    sw      s4, 20(sp)
    sw      s5, 24(sp)
    sw      s6, 28(sp)
    sw      s7, 32(sp)
    sw      s8, 36(sp)
    sw      s9, 40(sp)
    sw      s10, 44(sp)
    sw      s11, 48(sp)

# Make sure the input is exactly 14 characters: none of the first 14 is
# NUL and the 15th is. Each character minus '1' goes into state.
    addi    s1, a0, 0
    addi    t0, zero, 14
    addi    t1, zero, 0
    la      t3, state
loop1:
    add     t6, s1, t1
    lbu     t2, 0(t6)
    beqz    t2, invalid
    add     t4, t3, t1
    addi    t2, t2, -49             # '1' is 49: '1' -> 0, '7' -> 6
    sb      t2, 0(t4)
    addi    t1, t1, 1
    blt     t1, t0, loop1

    lbu     t2, 14(s1)
    bnez    t2, invalid

# The first 7 values must be 0 to 6 with no repeats; the orientations
# must be 0 to 2 and add up to a multiple of 3.
    la      t0, state
    addi    t3, zero, 0             # i = 0
    addi    t4, zero, 7             # values must be below 7
    addi    t5, zero, 7             # 7 values
# seen keeps the marks of the previous call; without clearing, a valid
# input would be taken for a repeat.
    la      t6, seen
    sb      zero, 0(t6)
    sb      zero, 1(t6)
    sb      zero, 2(t6)
    sb      zero, 3(t6)
    sb      zero, 4(t6)
    sb      zero, 5(t6)
    sb      zero, 6(t6)
chk_p:
    lbu     t2, 0(t0)
    bge     t2, t4, invalid         # 7 or more: invalid
    add     t1, t6, t2              # t1 = address of seen[state[i]]
    lbu     t2, 0(t1)
    bne     t2, zero, invalid       # already marked: a repeat
    addi    t2, zero, 1
    sb      t2, 0(t1)               # mark it
    addi    t0, t0, 1
    addi    t3, t3, 1
    blt     t3, t5, chk_p
    addi    t4, zero, 3             # orientations must be below 3
    addi    t5, zero, 14            # up to the 14th value
    addi    t1, zero, 0             # sum = 0
chk_o:
    lbu     t2, 0(t0)               # t0 and t3 go on from chk_p
    bge     t2, t4, invalid         # 3 or more: invalid
    add     t1, t1, t2              # sum += state[i]
    addi    t0, t0, 1
    addi    t3, t3, 1
    blt     t3, t5, chk_o
# RV32I has no remainder instruction and the sum is small, so subtract 3
# until it is below 3.
mod3:
    blt     t1, t4, mod3_done       # sum < 3: done
    addi    t1, t1, -3
    j       mod3
mod3_done:
    bne     t1, zero, invalid       # remainder not 0: invalid

# p (0 to 5039): for each i, add fact[i] once for every later value that
# is smaller than state[i].
    la      s1, state
    la      s2, fact                # s2 points at fact[0] = 720
    addi    s0, zero, 0             # p = 0
    addi    t0, zero, 0             # i = 0
    addi    t4, zero, 7
outer:
    add     t6, s1, t0
    lbu     t2, 0(t6)               # t2 = state[i]
    lw      t5, 0(s2)               # t5 = fact[i]
    addi    t1, t0, 1               # j = i + 1
inner:
    bge     t1, t4, inner_done      # j reached 7: this i is done
    add     t6, s1, t1
    lbu     t3, 0(t6)               # t3 = state[j]
    bge     t3, t2, skip            # state[j] not smaller: skip
    add     s0, s0, t5              # smaller: p += fact[i]
skip:
    addi    t1, t1, 1
    j       inner
inner_done:
    addi    s2, s2, 4               # fact is .word: next entry is 4 on
    addi    t0, t0, 1
    blt     t0, t4, outer

# o: the first 6 orientations form a base-3 number; the 7th follows
# from the sum.
    addi    s3, zero, 0             # o = 0
    addi    t0, zero, 7             # from state[7]
    addi    t4, zero, 13            # to state[12]
ori_loop:
    add     t6, s1, t0
    lbu     t2, 0(t6)               # t2 = state[t0]
    add     t5, s3, s3              # t5 = 2o
    add     s3, s3, t5              # o = 3o
    add     s3, s3, t2              # o = 3o + state[t0]
    addi    t0, t0, 1
    blt     t0, t4, ori_loop

    la      s7, move_face
    la      s8, p_move_rows_asm
    la      s9, group_start_asm
    la      s10, o_move_rows_asm
    la      s11, group_orientation_asm
    addi    s2, zero, 9             # s2 now holds the constant 9
    addi    s5, zero, 0             # bound = 0

# Each round restarts from the input; last = 9 means no previous move.
new_bound:
    la      s4, frames
    addi    s6, zero, 0             # depth = 0
    sw      s0, 0(s4)               # frame.p = p of the input
    sw      s3, 4(s4)               # frame.o = o of the input
    addi    t0, zero, 0
    sw      t0, 8(s4)               # frame.next = 0: try R first
    sw      s2, 12(s4)              # frame.last = 9

# At the given depth, check whether the state joins a table solution.
# The entries of p are group_start[p] <= i < group_start[p + 1]; the one
# whose orientation is o is the state. Not in the table: go back.
try_move:
    bne     s6, s5, search          # depth != bound: keep searching
    lw      t2, 0(s4)               # p
    lw      t3, 4(s4)               # o
    slli    t4, t2, 1               # group_start is .half: p * 2
    add     t4, s9, t4
    lhu     t6, 0(t4)               # i = group_start[p]
    lhu     t0, 2(t4)               # end = group_start[p + 1]
find_loop:
    bgeu    t6, t0, back            # past the end: not in the table
    slli    t5, t6, 1
    add     t5, t5, s11
    lhu     t5, 0(t5)               # group_orientation[i]
    bne     t5, t3, find_next
    addi    s1, t6, 0               # keep the index for found
    j       found

find_next:
    addi    t6, t6, 1
    j       find_loop

# Consecutive turns of one face can be merged, so they are not searched.
search:
    lw      t1, 8(s4)               # m = frame.next
    beq     t1, s2, back            # m == 9: all 9 moves tried, go back
    addi    t0, t1, 1               # next = m + 1: where to resume
    sw      t0, 8(s4)
    add     t2, s7, t1
    lbu     t2, 0(t2)               # t2 = move_face[m]
    lw      t3, 12(s4)
    add     t3, s7, t3
    lbu     t3, 0(t3)               # t3 = move_face[last]
    beq     t2, t3, try_move        # same face: skip this m

# p_move_rows_asm and o_move_rows_asm hold one pointer per face: the
# first load finds the table of this face, the second, in rot_loop, reads
# the state after one quarter turn. R2 is two turns, R' is three.
    slli    t0, t2, 2               # pointers are .word: face * 4
    add     a3, s8, t0
    lw      a3, 0(a3)               # a3 = p table of this face
    add     a4, s10, t0
    lw      a4, 0(a4)               # a4 = o table of this face
    lw      t4, 0(s4)               # np = p
    lw      t6, 4(s4)               # no = o
    la      a5, move_turns
    add     a5, a5, t1
    lbu     a5, 0(a5)               # a5 = move_turns[m]
rot_loop:
    slli    t0, t4, 1               # the tables are .half: index * 2
    add     t0, a3, t0
    lhu     t4, 0(t0)               # np = p_move[np]
    slli    t0, t6, 1
    add     t0, a4, t0
    lhu     t6, 0(t0)               # no = o_move[no]
    addi    a5, a5, -1
    bnez    a5, rot_loop

    addi    s4, s4, 16              # s4 to the next level
    addi    s6, s6, 1               # depth + 1
    sw      t4, 0(s4)               # new level: p = np
    sw      t6, 4(s4)               # o = no
    sw      zero, 8(s4)             # next = 0: start from R
    sw      t1, 12(s4)              # last = m, the move just made
    j       try_move                # go on at the new level

# When the root has tried every move, increase bound; otherwise go back
# one level. At most 6 moves come before the table and at most 5 from it.
back:
    bne     s6, zero, pop           # not level 0: go back one level
    addi    s5, s5, 1               # level 0 is done too: bound + 1
    addi    t0, zero, 6
    bgt     s5, t0, invalid         # bound above 6: give up
    j       new_bound               # search again with the new bound

pop:
    addi    s4, s4, -16             # s4 back to the previous level
    addi    s6, s6, -1              # depth - 1
    j       try_move                # resume that level from its next

# The first half comes from the search: move i is frames[i + 1].last.
# frames[1].last is at 16 + 12 = 28, and each level is 16 bytes on.
found:
    la      t0, frames
    addi    t0, t0, 28
    la      t1, solution
    addi    t2, zero, 0             # i = 0
found_loop:
    bge     t2, s6, next            # i == depth: first half done
    lw      t3, 0(t0)               # frames[i + 1].last
    sb      t3, 0(t1)               # solution[i]
    addi    t0, t0, 16
    addi    t1, t1, 1
    addi    t2, t2, 1
    j       found_loop

# The second half follows the table to the solved cube: take
# group_move[index], turn by it, and look the new state up. The turn and
# the lookup are written again here: the search has to go back, while
# this part only follows the table, so the two are kept apart.
#   s0, s3: current state (cp, co)   s5: length   t1: next cell of
#   solution   a7: m
next:
    mv      s5, s6                  # length = depth
    lw      s0, 0(s4)               # cp = frames[depth].p
    lw      s3, 4(s4)               # co = frames[depth].o
half_loop:
    bnez    s0, half_body           # cp != 0: not solved yet
    beqz    s3, half_done           # co == 0 as well: solved
half_body:
    la      t2, group_move_asm
    add     t2, t2, s1              # group_move is .byte: no scaling
    lbu     a7, 0(t2)               # m = group_move[index]
    sb      a7, 0(t1)               # solution[length] = m
    addi    t1, t1, 1
    addi    s5, s5, 1               # length + 1

    add     t2, s7, a7
    lbu     t2, 0(t2)               # t2 = move_face[m]
    slli    t0, t2, 2
    add     a3, s8, t0
    lw      a3, 0(a3)               # a3 = p table of this face
    add     a4, s10, t0
    lw      a4, 0(a4)               # a4 = o table of this face
    mv      t4, s0                  # np = cp
    mv      t6, s3                  # no = co
    la      a5, move_turns
    add     a5, a5, a7
    lbu     a5, 0(a5)               # a5 = move_turns[m]
rot_loop2:
    slli    t0, t4, 1
    add     t0, a3, t0
    lhu     t4, 0(t0)
    slli    t0, t6, 1
    add     t0, a4, t0
    lhu     t6, 0(t0)
    addi    a5, a5, -1
    bnez    a5, rot_loop2
    mv      s0, t4                  # cp = np
    mv      s3, t6                  # co = no

    slli    t4, s0, 1
    add     t4, s9, t4
    lhu     t6, 0(t4)               # i = group_start[cp]
    lhu     t0, 2(t4)               # end = group_start[cp + 1]
find_loop2:
    bgeu    t6, t0, invalid         # cannot happen: every state on the
                                    # way is in the table
    slli    t5, t6, 1
    add     t5, t5, s11
    lhu     t5, 0(t5)
    bne     t5, s3, find_next2
    addi    s1, t6, 0               # the new index
    j       half_loop

find_next2:
    addi    t6, t6, 1
    j       find_loop2

# Compute the space needed: 1 for the NUL, the characters of each name,
# and length - 1 spaces.
#   t0: k   t1: next cell of solution   t2: f   t5: address of the name
half_done:
    la      t1, solution
    addi    t0, zero, 1             # k = 1
    addi    t2, zero, 0             # f = 0
k_loop:
    bge     t2, s5, k_done
    lbu     t3, 0(t1)
    slli    t3, t3, 1               # names are 2 bytes: m * 2
    la      t5, move_names
    add     t5, t5, t3
    addi    t0, t0, 1               # the first character
    lbu     t4, 1(t5)
    beqz    t4, k_skip              # no second character
    addi    t0, t0, 1
k_skip:
    addi    t1, t1, 1
    addi    t2, t2, 1
    j       k_loop
k_done:
    beqz    s5, k_end               # no move: no space
    add     t0, t0, s5
    addi    t0, t0, -1              # length - 1 spaces
# Check the size. When the answer does not fit, leave an empty string if
# there is room for the NUL, and return -2.
k_end:
    bleu    t0, a2, cap_ok          # k <= cap (unsigned): it fits
    beqz    a2, cap_ret             # cap 0: no room even for the NUL
    sb      zero, 0(a1)
cap_ret:
    li      a0, -2
    j       done

# Then write the solution: a space before every name but the first, the
# name, and the NUL at the end.
#   t1: next cell of solution   t2: f   t6: next cell of out
cap_ok:
    la      t1, solution
    mv      t6, a1
    addi    t2, zero, 0             # f = 0
w_loop:
    bge     t2, s5, w_done
    beqz    t2, w_name              # first name: no space before it
    addi    t5, zero, 32            # ' '
    sb      t5, 0(t6)
    addi    t6, t6, 1
w_name:
    lbu     t3, 0(t1)
    slli    t3, t3, 1
    la      t5, move_names
    add     t5, t5, t3
    lbu     t4, 0(t5)               # the first character
    sb      t4, 0(t6)
    addi    t6, t6, 1
    lbu     t4, 1(t5)
    beqz    t4, w_next              # no second character
    sb      t4, 0(t6)
    addi    t6, t6, 1
w_next:
    addi    t1, t1, 1
    addi    t2, t2, 1
    j       w_loop
w_done:
    sb      zero, 0(t6)
    mv      a0, s5                  # return the length
    j       done

# Invalid input: return -1.
invalid:
    li      a0, -1
    j       done

done:
    lw      ra, 0(sp)
    lw      s0, 4(sp)
    lw      s1, 8(sp)
    lw      s2, 12(sp)
    lw      s3, 16(sp)
    lw      s4, 20(sp)
    lw      s5, 24(sp)
    lw      s6, 28(sp)
    lw      s7, 32(sp)
    lw      s8, 36(sp)
    lw      s9, 40(sp)
    lw      s10, 44(sp)
    lw      s11, 48(sp)
    addi    sp, sp, 64
    ret
    .size   rubik_solve_asm, .-rubik_solve_asm
