struct Input { int a; int b; };
struct Output { int x; };

void outsource(struct Input *input, struct Output *output)
{
    int a = input->a;
    int b = input->b;
#if ISEKAI_C_PARSER
    if (a == 0) {
        b = b + 1;
    }
#else
    while (a || b++) {
        a++;
    }
#endif
    output->x = input->a;
}
