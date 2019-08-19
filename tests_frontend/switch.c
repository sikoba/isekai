struct Input { int a; int b; };
struct Output { int x; };

void outsource(struct Input *input, struct Output *output)
{
    int a = input->a;
#if ISEKAI_C_PARSER
    if (a == 0) {
        a = a + 12;
    } else if (a == 77) {
        a = a + 33;
    } else if (a == 185) {
        a = a * 8;
    } else {
        a = a * 2;
    }
#else
    switch (a) {
    case 0: a += 12; break;
    case 77: a += 33; break;
    case 185: a *= 8; break;
    default: a *= 2; break;
    }
#endif
    output->x = a + 1;
}
