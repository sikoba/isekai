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
#include <inttypes.h>
#include <stdlib.h>
#include <unistd.h>
typedef libff::Fr<libff::default_ec_pp> FieldT;
using namespace libff;
using namespace libsnark;
using namespace gadgetlib2;

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

static void felem_print_bits(FElem v, int nbits)
{
    for (int i = 64 - 1; i >= 0; --i) {
        const int bit = (i < nbits) ? v.getBit(i, R1P) : 0;
        putc('0' + bit, stdout);
    }
    putc('\n', stdout);
}

static void felem_check_bits(FElem v, int from, int to, const char *what)
{
    for (int i = from; i < to; ++i) {
        if (v.getBit(i, R1P)) {
            fprintf(stderr, "Error: %s: found set bit after position %d (at %d)\n", what, from, i);
            exit(1);
        }
    }
}

static uint64_t felem_to_uint(FElem v, int nbits)
{
    uint64_t r = 0;
    for (int i = 0; i < nbits; ++i)
        r |= static_cast<uint64_t>(v.getBit(i, R1P)) << i;
    return r;
}

static uint64_t felem_to_uint_check(FElem v, int width, int max_width, const char *what)
{
    felem_check_bits(v, width, max_width, what);
    return felem_to_uint(v, width);
}

// We can't directly assign a 'uint64_t' to a 'FieldT' because it gets interpreted as a signed
// value: if it has the most significant bit set, the result will be negative-modulo-p.
//
// This is really stupid and should probably be fixed in gadgetlib2's upstream, but whatever.
static void fieldt_from_uint64(FieldT &v, uint64_t x)
{
    v =  ((x >> 48) & 0xFFFFu);
    v *= 0x10000u;
    v += ((x >> 32) & 0xFFFFu);
    v *= 0x10000u;
    v += ((x >> 16) & 0xFFFFu);
    v *= 0x10000u;
    v += ((x >>  0) & 0xFFFFu);
}

static void print_usage_and_exit(const std::string &msg = "")
{
    if (!msg.empty())
        fprintf(stderr, "Error: %s.\n", msg.c_str());
    fprintf(stderr, "USAGE: judge [-w <width>] [-c <fd>] [-s <width>] <arithmetic circuit file>\n");
    exit(2);
}

int main(int argc, char **argv)
{
    unsigned output_width = 64;
    unsigned cost_fd = 2; // stderr
    unsigned max_width = 512;
    for (int c; (c = getopt(argc, argv, "w:c:s:")) != -1;) {
        switch (c) {
        case 'w':
            parse_uint_until_nul(optarg, output_width, /*base=*/10);
            break;
        case 'c':
            parse_uint_until_nul(optarg, cost_fd, /*base=*/10);
            break;
        case 's':
            parse_uint_until_nul(optarg, max_width, /*base=*/10);
            break;
        default:
            print_usage_and_exit();
        }
    }
    const int nposarg = argc - optind;
    if (nposarg != 1)
        print_usage_and_exit("expected exactly one positional argument");

    const std::string arci_filename = argv[optind];

    libff::default_ec_pp::init_public_params();

    FieldT one = FieldT::one();
    FieldT zero = FieldT::zero();
    FieldT minus_one = -1;

    std::vector<FieldT> wires;
    {
        ValueListReader reader(arci_filename + ".in");
        while (auto value = reader.next_value()) {
            FieldT res;
            parse_uint_until_nul(value.hex, res, /*base=*/16);
            wires.emplace_back(res);
        }
    }

    CircuitReader reader(arci_filename);
    wires.resize(reader.total());
    uint64_t cost = 0;
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
                parse_uint_until_nul(command.inline_hex, arg, /*base=*/16);
                wires.at(command.outputs[0]) = wires.at(command.inputs[0]) * arg;
            }
            break;
        case Opcode::CONST_MUL_NEG:
            {
                CHECK(command.inputs.size() == 1);
                CHECK(command.outputs.size() == 1);
                FieldT arg;
                parse_uint_until_nul(command.inline_hex, arg, /*base=*/16);
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
                const unsigned noutputs = command.outputs.size();
                for (unsigned i = 0; i < noutputs; ++i) {
                    wires.at(command.outputs[i]) = v.getBit(i, R1P);
                }
                felem_check_bits(v, noutputs, max_width, "split");
                cost += noutputs + 1;
            }
            break;
        case Opcode::OUTPUT:
            CHECK(command.inputs.size() == 1);
            felem_print_bits(wires.at(command.inputs[0]), output_width);
            break;
        case Opcode::DLOAD:
            {
                CHECK(command.inputs.size() > 1);
                CHECK(command.outputs.size() == 1);
                FElem v = wires.at(command.inputs[0]);
                const uint64_t u = felem_to_uint_check(v, 63, max_width, "dload");
                CHECK(u + 1 < command.inputs.size());
                wires.at(command.outputs[0]) = wires.at(command.inputs[u + 1]);
            }
            break;
        case Opcode::ASPLIT:
            {
                CHECK(command.inputs.size() == 1);
                FElem v = wires.at(command.inputs[0]);
                const unsigned noutputs = command.outputs.size();
                for (unsigned i = 0; i < noutputs; ++i) {
                    wires.at(command.outputs[i]) = (v == i) ? one : zero;
                }
            }
            break;
        case Opcode::INT_DIV:
            {
                CHECK(command.inputs.size() == 3);
                CHECK(command.outputs.size() == 2);
                const unsigned w = command.inputs[0];
                CHECK(w <= 64);
                FElem a = wires.at(command.inputs[1]);
                FElem b = wires.at(command.inputs[2]);
                const uint64_t x = felem_to_uint_check(a, w, max_width, "div_N");
                const uint64_t y = felem_to_uint_check(b, w, max_width, "div_N");
                CHECK(y != 0);
                fieldt_from_uint64(
                    wires.at(command.outputs[0]),
                    x / y);
                fieldt_from_uint64(
                    wires.at(command.outputs[1]),
                    x % y);
            }
            break;
        case Opcode::FIELD_DIV:
            {
                CHECK(command.inputs.size() == 2);
                CHECK(command.outputs.size() == 1);
                FieldT a = wires.at(command.inputs[0]);
                FieldT b = wires.at(command.inputs[1]);
                CHECK(b != zero);
                wires.at(command.outputs[0]) = a * b.inverse();
            }
            break;
        }
    }
    dprintf(cost_fd, "Cost: %" PRIu64 "\n", cost);
}
