struct Input {
    int a;
    int b;
    int c;
    int A, B, C, D, E, F, G, H;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
#define I(Field_) input->Field_
#if ISEKAI_C_PARSER
    if (input->a != 0) {
        if (input->b != 0) {
            if (input->c != 0) {
                output->x = I(A);
            } else {
                output->x = I(B);
            }
        } else {
            if (input->c != 0) {
                output->x = I(C);
            } else {
                output->x = I(D);
            }
        }
    } else {
        if (input->b != 0) {
            if (input->c != 0) {
                output->x = I(E);
            } else {
                output->x = I(F);
            }
        } else {
            if (input->c != 0) {
                output->x = I(G);
            } else {
                output->x = I(H);
            }
        }
    }
#else
    output->x = input->a
        ? (input->b ? (input->c ? I(A) : I(B)) : (input->c ? I(C) : I(D)))
        : (input->b ? (input->c ? I(E) : I(F)) : (input->c ? I(G) : I(H)));
#endif
}
