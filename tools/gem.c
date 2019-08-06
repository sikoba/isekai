struct Input {
    int v1, v2, v3, v4, v5;
};

struct Output {
    int x;
};

void outsource(struct Input *in, struct Output *out)
{
#if ISEKAI_C_PARSER
    int tmp = 0xDEAD;

#define S3_TRUE \
    tmp = 1;

#define S3_FALSE \
    tmp = (in->v5 != 0);

#define S2_TRUE \
    if (in->v4 != 0) { \
        S3_TRUE \
    } else { \
        S3_FALSE \
    }

#define S2_FALSE \
    S3_FALSE

#define S1_TRUE \
    S2_TRUE

#define S1_FALSE \
    if (in->v3 != 0) { \
        S2_TRUE \
    } else { \
        S2_FALSE \
    }

    if (in->v1 != 0) {
        if (in->v2 != 0) {
            S1_TRUE
        } else {
            S1_FALSE
        }
    } else {
        S1_FALSE
    }

#else
    int tmp = (((in->v1 && in->v2) || in->v3) && in->v4) || in->v5;
#endif
    out->x = tmp;
}
