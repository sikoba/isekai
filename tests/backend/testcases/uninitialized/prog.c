struct Input {
    unsigned a;
};

struct Output {
    unsigned x;
    // This field is left uninitialized; the backend generates zero for such a
    // field, and the boilerplate generator initializes the output structure
    // with a {0} initializer, meaning that all fields will be initialized to
    // zero.
    unsigned y;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = input->a;
}
