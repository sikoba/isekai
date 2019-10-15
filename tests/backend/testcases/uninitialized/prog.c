struct Input {
    unsigned a;
};

struct Output {
    unsigned x;
    // This field is left uninitialized; the backend generates zero for such a
    // field, and the boilerplate generator initializes the output structure
    // with zero values. That's what we test here.
    unsigned y;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = input->a;
}
