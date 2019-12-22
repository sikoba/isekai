#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#ifndef __cplusplus
#   include <stdbool.h>
#endif

#ifdef __cplusplus
#   define NAGAI_NOTHROW_ __attribute__((nothrow))
#else
#   define NAGAI_NOTHROW_ /*nothing*/
#endif

struct Nagai;
typedef struct Nagai Nagai;

// Initializes a Nagai from the value of x.
Nagai *nagai_init_pos(uint64_t x) NAGAI_NOTHROW_;

// Initializes a Nagai from the value of -x.
Nagai *nagai_init_neg(uint64_t x) NAGAI_NOTHROW_;

// Initializes a Nagai from a string constant in base 10, possibly prepended with minus sign.
Nagai *nagai_init_from_str(const char *s) NAGAI_NOTHROW_;

Nagai *nagai_copy(Nagai *) NAGAI_NOTHROW_;

// This operation is guaranteed to be cached, that is, the 'split' operation is only done once when
// 'nagai_getbit(n, pos_0)' is called for the first time; all other 'nagai_getbit' requests for this
// pointer 'n' will use the same split results, thus being "zero-cost".
Nagai *nagai_getbit(Nagai *, uint64_t pos) NAGAI_NOTHROW_;

// This operation is also guaranteed to be cached.
uint64_t nagai_lowbits(Nagai *) NAGAI_NOTHROW_;

Nagai *nagai_add(Nagai *, Nagai *) NAGAI_NOTHROW_;
Nagai *nagai_mul(Nagai *, Nagai *) NAGAI_NOTHROW_;
Nagai *nagai_div(Nagai *, Nagai *) NAGAI_NOTHROW_;
bool nagai_nonzero(Nagai *) NAGAI_NOTHROW_;

void nagai_free(Nagai *) NAGAI_NOTHROW_;

static inline __attribute__((always_inline, unused)) NAGAI_NOTHROW_
Nagai *nagai_inv(Nagai *a)
{
    Nagai *unity = nagai_init_pos(1);
    Nagai *result = nagai_div(unity, a);
    nagai_free(unity);
    return result;
}

static inline __attribute__((always_inline, unused)) NAGAI_NOTHROW_
Nagai *nagai_exp(Nagai *b, Nagai *e, unsigned limit)
{
    Nagai *r = nagai_init_pos(1);
    for (unsigned i = 0; i < limit; ++i) {
        Nagai *bit = nagai_getbit(e, i);
        // Yes, we sort of "leak" "memory" here...
        // Anyway, in isekai, 'nagai_free()' currently does nothing.
        if (nagai_nonzero(bit)) {
            // r *= b;
            r = nagai_mul(r, b);
        }
        // b *= b;
        b = nagai_mul(b, b);
    }
    return r;
}

static inline __attribute__((always_inline, unused)) NAGAI_NOTHROW_
Nagai *nagai_sub(Nagai *a, Nagai *b)
{
    Nagai *neg = nagai_init_neg(1);
	Nagai *b_neg = nagai_mul(b, neg);
    Nagai *result = nagai_add(a, b_neg);
    nagai_free(neg);
	nagai_free(b_neg);
    return result;
}

#undef NAGAI_NOTHROW_

#ifdef __cplusplus
}
#endif
