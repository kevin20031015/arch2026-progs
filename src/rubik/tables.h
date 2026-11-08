#include <stdint.h>

/* Each table has three rows: one quarter turn of R, B and D. */
extern const uint16_t *const p_move_rows[3];
extern const uint16_t *const o_move_rows[3];

/* The entries of permutation p are
 *   group_start[p] <= i < group_start[p + 1]
 * Each entry holds an orientation index and the next move toward the solved
 * state.
 */
extern const uint16_t group_start[5041];
extern const uint16_t group_orientation[];
extern const uint8_t group_move[];
