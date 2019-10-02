struct Input {
    int a;
    int b;
    int c;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    struct Box { int value; };

    struct Box p;
    p.value = input->b;

    struct Box q;
    q.value = input->c;

    struct Box *ptr = input->a ? &p : &q;
    output->x = ptr->value;
}
