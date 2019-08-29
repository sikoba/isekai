#define _POSIX_C_SOURCE 200809L
#include "value_list_reader.hpp"
#include "circuit_reader.hpp"
#include "common.hpp"
#include <libsnark/gadgetlib2/integration.hpp>
#include <libsnark/gadgetlib2/adapters.hpp>
#include <libff/common/default_types/ec_pp.hpp>
#include <string>
#include <vector>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
typedef libff::Fr<libff::default_ec_pp> FieldT;
using namespace libff;
using namespace libsnark;
using namespace gadgetlib2;

static void init_pp()
{
#if defined(CURVE_BN128)
    bn128_pp::init_public_params();
#elif defined(CURVE_ALT_BN128)
    alt_bn128_pp::init_public_params();
#elif defined(CURVE_EDWARDS)
    edwards_pp::init_public_params();
#elif defined(CURVE_MNT4)
    mnt4_pp::init_public_params();
#elif defined(CURVE_MNT6)
    mnt6_pp::init_public_params();
#else
#   error "Unknown curve."
#endif
}

static void check_failed(const char *expr, const char *file, int line)
{
    fprintf(stderr, "CHECK(%s) failed at %s:%d.\n", expr, file, line);
    abort();
}

#define CHECK(expr) \
    do { \
        if (!(expr)) { \
            check_failed(#expr, __FILE__, __LINE__); \
        } \
    } while (0)

static void print_field_bits(FElem v, int nbits)
{
    for (int i = 64 - 1; i >= 0; --i) {
        const int bit = (i < nbits) ? v.getBit(i, R1P) : 0;
        putc('0' + bit, stdout);
    }
    putc('\n', stdout);
}

static void print_usage_and_exit(const std::string &msg = "")
{
    if (!msg.empty()) {
        fprintf(stderr, "Error: %s.\n", msg.c_str());
    }
    fprintf(stderr, "USAGE: judge [-w <width>] [-c <fd>] [-s <width>] <arithmetic circuit file>\n");
    exit(2);
}

int main(int argc, char **argv)
{
    unsigned output_width = 64;
    unsigned cost_fd = 2; // stderr
    unsigned split_check_bits = 1024;
    for (int c; (c = getopt(argc, argv, "w:c:s:")) != -1;) {
        switch (c) {
        case 'w':
            parse_uint_until_nul(optarg, output_width, BaseDec{});
            break;
        case 'c':
            parse_uint_until_nul(optarg, cost_fd, BaseDec{});
            break;
        case 's':
            parse_uint_until_nul(optarg, split_check_bits, BaseDec{});
            break;
        default:
            print_usage_and_exit();
        }
    }
    const int nposarg = argc - optind;
    if (nposarg != 1) {
        print_usage_and_exit("expected exactly one positional argument");
    }
    const std::string arci_filename = argv[optind];

    init_pp();

    FieldT one = FieldT::one();
    FieldT zero = FieldT::zero();
    FieldT minus_one = -1;

    std::vector<FieldT> wires;
    {
        ValueListReader reader(arci_filename + ".in");
        while (auto value = reader.next_value()) {
            FieldT res;
            parse_uint_until_nul(value.hex, res, BaseHex{});
            wires.emplace_back(res);
        }
    }

    CircuitReader reader(arci_filename);
    wires.resize(reader.total());
    unsigned long cost = 0;
    while (auto command = reader.next_command()) {
        switch (command.opcode) {
        case Opcode::INPUT:
        case Opcode::NIZK_INPUT:
            // do nothing
            break;
        case Opcode::ADD:
            CHECK(command.inputs.size() == 2);
            CHECK(command.outputs.size() == 1);
            wires.at(command.outputs[0]) = wires.at(command.inputs[0]) + wires.at(command.inputs[1]);
            break;
        case Opcode::MUL:
            CHECK(command.inputs.size() == 2);
            CHECK(command.outputs.size() == 1);
            wires.at(command.outputs[0]) = wires.at(command.inputs[0]) * wires.at(command.inputs[1]);
            ++cost;
            break;
        case Opcode::CONST_MUL:
            {
                CHECK(command.inputs.size() == 1);
                CHECK(command.outputs.size() == 1);
                FieldT arg;
                parse_uint_until_nul(command.inline_hex, arg, BaseHex{});
                wires.at(command.outputs[0]) = wires.at(command.inputs[0]) * arg;
            }
            break;
        case Opcode::CONST_MUL_NEG:
            {
                CHECK(command.inputs.size() == 1);
                CHECK(command.outputs.size() == 1);
                FieldT arg;
                parse_uint_until_nul(command.inline_hex, arg, BaseHex{});
                wires.at(command.outputs[0]) = wires.at(command.inputs[0]) * arg * minus_one;
            }
            break;
        case Opcode::ZEROP:
            cost += 2;
            CHECK(command.inputs.size() == 1);
            CHECK(command.outputs.size() == 2);
            wires.at(command.outputs[1]) = wires.at(command.inputs[0]) == zero ? zero : one;
            break;
        case Opcode::SPLIT:
            {
                CHECK(command.inputs.size() == 1);
                FElem v = wires.at(command.inputs[0]);
                const size_t noutputs = command.outputs.size();
                for (size_t i = 0; i < noutputs; ++i) {
                    wires.at(command.outputs[i]) = v.getBit(i, R1P);
                }
                for (unsigned i = noutputs; i < split_check_bits; ++i) {
                    if (v.getBit(i, R1P)) {
                        fprintf(stderr, "ERROR: invalid split: into %zu, found set bit at %u.\n",
                                noutputs, i);
                        return 1;
                    }
                }
                cost += noutputs + 1;
            }
            break;
        case Opcode::OUTPUT:
            CHECK(command.inputs.size() == 1);
            print_field_bits(wires.at(command.inputs[0]), output_width);
            break;
        }
    }
    dprintf(cost_fd, "Cost: %lu\n", cost);
}
