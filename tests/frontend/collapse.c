struct Input { int a; int b; };
struct Output { int x; };

void outsource(struct Input *input, struct Output *output)
{
    (void) input;
    int a = 0;
    a = a + 3;
    a = a + 4;
    a = a + 5;
    output->x = a;
}
