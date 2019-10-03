struct Input {
    int a;
};

struct Output {
    unsigned check_add_u;
    unsigned check_add_s;
    unsigned check_sub_u;
    unsigned check_sub_s;
    unsigned check_mul_u;
    unsigned check_mul_s;
    unsigned check_div_u;
    unsigned check_mod_u;
    int check_rsh_s;
    unsigned check_eq;
    unsigned check_ne;
    unsigned check_lt_u;
    unsigned check_le_u;
    unsigned check_lt_s;
    unsigned check_le_s;
};

void outsource(struct Input *input, struct Output *output)
{
#define STORE(T_, Dst_, A_, Op_, B_) \
    do { \
        T_ tmp_a = (A_); \
        T_ tmp_b = (B_); \
        (Dst_) = tmp_a Op_ tmp_b; \
    } while (0)

    (void) input;
    STORE(unsigned, output->check_add_u, 4294967295u, +,  33u);
    STORE(unsigned, output->check_add_s, 2147483647u, +,  1u);
    STORE(unsigned, output->check_sub_u, 12u,         -,  567u);
    STORE(unsigned, output->check_sub_s, 2147483648u, -,  1u);
    STORE(unsigned, output->check_mul_u, 3333333333u, *,  8901u);
    STORE(unsigned, output->check_mul_s, 2147483648u, *,  4294967295u);

    STORE(unsigned, output->check_div_u, 1440u,       /,  7u);
    STORE(unsigned, output->check_mod_u, 1440u,       %,  7u);

    STORE(unsigned, output->check_eq,    2,           ==, 2);
    STORE(unsigned, output->check_ne,    2,           !=, 2);
    STORE(unsigned, output->check_lt_u,  0u,          <,  4294967295u);
    STORE(unsigned, output->check_le_u,  0u,          <=, 4294967295u);
    STORE(int,      output->check_lt_s,  0,           <,  -1);
    STORE(int,      output->check_le_s,  0,           <=, -1);

    STORE(int,      output->check_rsh_s, -34,         >>, 1);
}
