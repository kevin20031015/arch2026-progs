/*
 * Optimal solver for the 2x2x2 Rubik's Cube: search the first part, then
 * finish the solution with the table. The search goes forward at most 6
 * moves from the input; the table (tables.c) holds every state within 5 moves
 * of the solved cube.
 */
#include "rubik.h"
#include "tables.h"

/*
 * The factorials for ranking the permutation (fact), and for each move its face
 * (move_face; 3 means no previous move), its number of quarter turns
 * (move_turns) and its name (move_names).
 */
static const uint32_t fact[7] = {720, 120, 24, 6, 2, 1, 1};
static const uint8_t move_face[10] = {
    0, 0, 0, 1, 1, 1, 2, 2, 2, 3,
};

static const uint8_t move_turns[9] = {1, 2, 3, 1, 2, 3, 1, 2, 3};

static const char move_names[9][3] = {"R",  "R2", "R'", "B", "B2",
                                      "B'", "D",  "D2", "D'"};

/*
 * One search level: the current state (p, o), the next move to try and the
 * move that led here.
 */
typedef struct {
    uint32_t p, o, next, last;
} frame_t;

/*
 * Find the state (p, o) in the table by its permutation and orientation.
 * Returns its entry, or -1 when it is not within 5 moves of solved.
 */
static int find_state(uint32_t p, uint32_t o)
{
    uint32_t i;

    for (i = group_start[p]; i < group_start[p + 1]; i++)
        if (group_orientation[i] == o)
            return (int) i;
    return -1;
}


int rubik_solve(const char *state, char *out, size_t cap)
{
    uint8_t digit[14];
    uint8_t seen[7] = {0};
    uint32_t i, j, p, o;
    uint32_t bound, depth, m, np, no, face, t;
    uint32_t sum;
    frame_t frames[7];
    int index;
    uint32_t cp, co;

    /* The input must be exactly 14 characters. */
    for (i = 0; i < 14; i++) {
        if (state[i] == '\0') {
            return -1;
        }
    }
    if (state[14] != '\0') {
        return -1;
    }

    /* Subtract '1' from each character to get the internal code. */
    for (i = 0; i < 14; i++) {
        digit[i] = state[i] - '1';
    }
    /* The first 7 values must be 0 to 6, with no repeats. */
    for (i = 0; i < 7; i++) {
        if (digit[i] >= 7)
            return -1;
        if (seen[digit[i]] == 1)
            return -1;
        seen[digit[i]] = 1;
    }
    /* Orientations must be 0 to 2, and their sum a multiple of 3. */
    sum = 0;
    for (i = 7; i < 14; i++) {
        if (digit[i] >= 3)
            return -1;
        sum = sum + digit[i];
    }
    while (sum >= 3)
        sum = sum - 3;
    if (sum != 0)
        return -1;
    /*
     * Rank the permutation p (0 to 5039) by counting the smaller values
     * after each one.
     */
    p = 0;
    for (i = 0; i < 7; i++) {
        for (j = i + 1; j < 7; j++) {
            if (digit[j] < digit[i])
                p = p + fact[i];
        }
    }
    /*
     * The first 6 orientations form a base-3 number; the 7th follows from
     * the sum.
     */
    o = 0;
    for (i = 7; i < 13; i++) {
        o = 3 * o + digit[i];
    }


    bound = 0;


/* Each round restarts from the input; last = 9 means no previous move. */
new_bound:
    depth = 0;
    frames[depth].p = p;
    frames[depth].o = o;
    frames[depth].next = 0;
    frames[depth].last = 9;


try_move:
    /* At the given depth, check whether the state joins a table solution. */
    if (depth == bound) {
        index = find_state(frames[depth].p, frames[depth].o);
        if (index >= 0)
            goto found;
        goto back;
    }
    m = frames[depth].next;
    if (m == 9)
        goto back;
    frames[depth].next = m + 1;
    /*
     * Consecutive turns of one face can be merged, so they are not
     * searched.
     */
    if (move_face[m] == move_face[frames[depth].last])
        goto try_move;


    face = move_face[m];
    np = frames[depth].p;
    no = frames[depth].o;

    /* R2 is two turns, R' is three. */
    for (t = 0; t < move_turns[m]; t++) {
        np = p_move_rows[face][np];
        no = o_move_rows[face][no];
    }

    depth = depth + 1;
    frames[depth].p = np;
    frames[depth].o = no;
    frames[depth].next = 0;
    frames[depth].last = m;
    goto try_move;
/*
 * When the root has tried every move, increase bound; otherwise go back
 * one level.
 */
back:
    if (depth != 0)
        goto pop;
    bound = bound + 1;
    /* At most 6 moves before the table, at most 5 in it. */
    if (bound > 6)
        goto fail;
    goto new_bound;

pop:
    depth = depth - 1;
    goto try_move;

fail:
    return -1;



/* The first half comes from the search, the second half from the table. */
found:
    uint8_t solution[11];
    int length = 0;
    /* First half: the moves of the search. */
    for (i = 0; i < depth; i++) {
        solution[i] = frames[i + 1].last;
        length++;
    }

    /* Second half: follow the table to the solved cube. */
    cp = frames[depth].p;
    co = frames[depth].o;
    while ((cp != 0) || (co != 0)) {
        m = group_move[index];
        solution[length] = m;
        face = move_face[m];
        length += 1;
        for (t = 0; t < move_turns[m]; t++) {
            cp = p_move_rows[face][cp];
            co = o_move_rows[face][co];
        }
        index = find_state(cp, co);
    }

    /* Compute the space needed, the NUL included. */
    size_t k = 1;
    int f;
    for (f = 0; f < length; f++) {
        if (move_names[solution[f]][1] == '\0') {
            k += 1;
        } else {
            k += 2;
        }
    }
    if (length > 0) {
        k += length - 1;
    }


    /* Check the size. */
    if (k > cap) {
        if (cap >= 1) {
            out[0] = '\0';
        }
        return -2;
    }

    /* Then write the solution. */
    int l = 0;

    for (f = 0; f < length; f++) {
        if (f != 0) {
            out[l] = ' ';
            l++;
        }
        out[l] = move_names[solution[f]][0];
        l++;
        if (move_names[solution[f]][1] != '\0') {
            out[l] = move_names[solution[f]][1];
            l++;
        }
    }

    out[l] = '\0';


    return length;
}
