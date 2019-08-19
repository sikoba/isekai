struct Input {
    int a;
    int b;
    int c;
    int v0, v1, v2, v3, v4, v5, v6, v7;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
#define I(Val_) input->v ## Val_
#if ISEKAI_C_PARSER
    if (input->a != 0) {
        if (input->b != 0) {
            if (input->c != 0) {
                output->x = I(0);
            } else {
                output->x = I(1);
            }
        } else {
            if (input->c != 0) {
                output->x = I(2);
            } else {
                output->x = I(3);
            }
        }
    } else {
        if (input->b != 0) {
            if (input->c != 0) {
                output->x = I(4);
            } else {
                output->x = I(5);
            }
        } else {
            if (input->c != 0) {
                output->x = I(6);
            } else {
                output->x = I(7);
            }
        }
    }
#else
    output->x = input->a
        ? (input->b ? (input->c ? I(0) : I(1)) : (input->c ? I(2) : I(3)))
        : (input->b ? (input->c ? I(4) : I(5)) : (input->c ? I(6) : I(7)));
#endif
}
