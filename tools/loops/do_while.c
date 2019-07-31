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

#   define BEGIN    a = a + 1; if (a != 48) {
#   define END      }

    BEGIN
        BEGIN
            BEGIN
                BEGIN
                END
            END
        END
    END

#else
    do {
        ++a;
    } while (a != 48);
#endif
    output->x = a + 5;
}
