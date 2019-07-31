struct Input {
    int a;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
    int a = input->a;
#if ISEKAI_C_PARSER

#   define BEGIN    if (a != 9) { a = a + 1;
#   define END      }

    BEGIN
        BEGIN
            BEGIN
            END
        END
    END

#else
    while (a != 9) {
        ++a;
    }
#endif
    output->x = a + 5;
}
