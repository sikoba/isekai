struct Input {
    int v1, v2, v3, v4, v5;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
#if ISEKAI_C_PARSER
    int tmp = 0xDEAD;

#define S3_TRUE \
    tmp = 1;

#define S3_FALSE \
    tmp = (input->v5 != 0);

#define S2_TRUE \
    if (input->v4 != 0) { \
        S3_TRUE \
    } else { \
        S3_FALSE \
    }

#define S2_FALSE \
    S3_FALSE

#define S1_TRUE \
    S2_TRUE

#define S1_FALSE \
    if (input->v3 != 0) { \
        S2_TRUE \
    } else { \
        S2_FALSE \
    }

    if (input->v1 != 0) {
        if (input->v2 != 0) {
            S1_TRUE
        } else {
            S1_FALSE
        }
    } else {
        S1_FALSE
    }

#else
    int tmp = (((input->v1 && input->v2) || input->v3) && input->v4) || input->v5;
#endif
    output->x = tmp;
}
