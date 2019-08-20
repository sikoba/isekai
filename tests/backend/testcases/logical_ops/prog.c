struct Input {
    int v1, v2, v3, v4, v5;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = (((input->v1 && input->v2) || input->v3) && input->v4) || input->v5;
}
