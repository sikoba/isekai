#include "value_list_reader.hpp"
#include "circuit_reader.hpp"
#include <libsnark/gadgetlib2/integration.hpp>
#include <libsnark/gadgetlib2/adapters.hpp>
#include <libff/common/default_types/ec_pp.hpp>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
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

#ifdef NDEBUG
#   error "Building with -DNDEBUG is not supported."
#endif

#define CHECK assert

static void print_field_bits(FElem v, int size)
{
    for (int i = size - 1; i >= 0; --i) {
        const int bit = v.getBit(i, R1P);
        putc('0' + bit, stdout);
    }
    putc('\n', stdout);
}

static FieldT hex_to_field(const char *hex)
{
    FieldT res;
    do {
        const char c = *hex;
        int digit;
        if ('0' <= c && c <= '9') {
            digit = c - '0';
        } else if ('a' <= c && c <= 'f') {
            digit = c - 'a' + 10;
        } else if ('A' <= c && c <= 'F') {
            digit = c - 'A' + 10;
        } else {
            fprintf(stderr, "Cannot parse symbol as a hex digit: code %d\n", (unsigned char) c);
            abort();
        }
        res *= 16;
        res += digit;
    } while (*(++hex));
    return res;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "USAGE: judge <circuit file>\n");
        return 2;
    }
    const std::string arci_filename = argv[1];

    init_pp();

    FieldT one = FieldT::one();
    FieldT zero = FieldT::zero();
    FieldT minus_one = -1;

    std::vector<FieldT> wires;
    {
        ValueListReader reader(arci_filename + ".in");
        while (auto value = reader.next_value()) {
            wires.emplace_back(hex_to_field(value.hex));
        }
    }

    CircuitReader reader(arci_filename);
    wires.resize(reader.total());
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
            break;
        case Opcode::CONST_MUL:
            CHECK(command.inputs.size() == 1);
            CHECK(command.outputs.size() == 1);
            wires.at(command.outputs[0]) = wires.at(command.inputs[0]) * hex_to_field(command.inline_hex);
            break;
        case Opcode::CONST_MUL_NEG:
            CHECK(command.inputs.size() == 1);
            CHECK(command.outputs.size() == 1);
            wires.at(command.outputs[0]) = wires.at(command.inputs[0]) * hex_to_field(command.inline_hex) * minus_one;
            break;
        case Opcode::ZEROP:
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
            }
            break;
        case Opcode::OUTPUT:
            CHECK(command.inputs.size() == 1);
            print_field_bits(wires.at(command.inputs[0]), 64);
            break;
        }
    }
}
