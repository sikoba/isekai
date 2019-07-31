struct Input {
    int a;
    int i;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
    int a = input->a;

#if ISEKAI_C_PARSER
    int i = input->i;
#   define BEGIN    if (i != 128) { a = a + a; i = i + 1;
#   define END      }

    BEGIN
        BEGIN
            BEGIN
            END
        END
    END

#else
    for (int i = input->i; i != 128; ++i) {
        a += a;
    }
#endif
    output->x = a + 5;
}
