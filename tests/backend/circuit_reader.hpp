#pragma once

#include "common.hpp"
#include "cfile.hpp"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <vector>
#include <string>

enum class Opcode {
    INPUT,
    NIZK_INPUT,
    ADD,
    MUL,
    CONST_MUL,
    CONST_MUL_NEG,
    ZEROP,
    SPLIT,
    OUTPUT,
    DLOAD,
    ASPLIT,
    INT_DIV,
    FIELD_DIV,
};

class CircuitReader
{
    template<class T>
    class ConstSlice
    {
        const T *start_;
        size_t size_;

    public:
        ConstSlice() : start_{nullptr}, size_{0} {}
        ConstSlice(const T *start, size_t size) : start_{start}, size_{size} {}
        T operator [](size_t i) const { return start_[i]; }
        size_t size() const { return size_; }
    };

    struct Command
    {
        Opcode opcode;
        ConstSlice<unsigned> inputs;
        ConstSlice<unsigned> outputs;
        char *inline_hex;
        bool ok;

        operator bool() const { return ok; }

        static Command invalid()
        {
            return Command{static_cast<Opcode>(0), {}, {}, nullptr, false};
        }
    };

    CFile file_;
    CFileLine line_;
    char *inline_hex_ = nullptr;
    std::vector<unsigned> inputs_buf_;
    std::vector<unsigned> outputs_buf_;

    void handle_inline_hex_(char *&s)
    {
        inline_hex_ = s;
        slurp_any_printable(s);
        char *inline_hex_end = s;
        slurp_some_ws(s);
        *inline_hex_end = '\0';
    }

    void reset_()
    {
        inputs_buf_.clear();
        outputs_buf_.clear();
        inline_hex_ = nullptr;
    }

    void read_inline_input_(char *&s)
    {
        unsigned u;
        slurp_uint(s, u, /*base=*/10);
        inputs_buf_.push_back(u);
        slurp_any_ws(s);
    }

    void read_args_part_(char *&s, std::vector<unsigned> &out)
    {
        unsigned nargs;
        slurp_uint(s, nargs, /*base=*/10);

        slurp_any_ws(s);
        slurp(s, "<");

        out.reserve(nargs);
        for (unsigned i = 0; i < nargs; ++i) {
            slurp_any_ws(s);
            unsigned u;
            slurp_uint(s, u, /*base=*/10);
            out.push_back(u);
        }

        slurp_any_ws(s);
        slurp(s, ">");

        slurp_any_ws(s);
    }

    void read_args_(char *s)
    {
        slurp(s, "in");
        slurp_some_ws(s);
        read_args_part_(s, inputs_buf_);

        slurp(s, "out");
        slurp_some_ws(s);
        read_args_part_(s, outputs_buf_);
    }

    Command make_command_(Opcode opcode)
    {
        return Command{
            opcode,
            ConstSlice<unsigned>{inputs_buf_.data(), inputs_buf_.size()},
            ConstSlice<unsigned>{outputs_buf_.data(), outputs_buf_.size()},
            inline_hex_,
            true,
        };
    }

    bool read_line_()
    {
        return line_.read_from(file_) > 0;
    }

    bool should_skip_line_()
    {
        return line_.c_str()[0] == '#';
    }

public:
    explicit CircuitReader(const char *path) : file_(path, "r") {}

    explicit CircuitReader(const std::string &path) : CircuitReader(path.c_str()) {}

    size_t total()
    {
        do {
            if (!read_line_())
                throw UnexpectedInput("error or EOF before 'total' line");
        } while (should_skip_line_());

        char *s = line_.c_str();

        slurp(s, "total");
        slurp_some_ws(s);

        unsigned u;
        slurp_uint(s, u, /*base=*/10);

        return u;
    }

    Command next_command()
    {
        reset_();

        do {
            if (!read_line_())
                return Command::invalid();
        } while (should_skip_line_());

        char *s = line_.c_str();

        if (maybe_slurp(s, "input", /*only_with_ws=*/true)) {
            read_inline_input_(s);
            return make_command_(Opcode::INPUT);
        }

        if (maybe_slurp(s, "nizkinput", /*only_with_ws=*/true)) {
            read_inline_input_(s);
            return make_command_(Opcode::NIZK_INPUT);
        }

        if (maybe_slurp(s, "output", /*only_with_ws=*/true)) {
            read_inline_input_(s);
            return make_command_(Opcode::OUTPUT);
        }

        if (maybe_slurp(s, "const-mul-neg-")) {
            handle_inline_hex_(s);
            read_args_(s);
            return make_command_(Opcode::CONST_MUL_NEG);
        }

        if (maybe_slurp(s, "const-mul-")) {
            handle_inline_hex_(s);
            read_args_(s);
            return make_command_(Opcode::CONST_MUL);
        }

        if (maybe_slurp(s, "add", /*only_with_ws=*/true)) {
            read_args_(s);
            return make_command_(Opcode::ADD);
        }

        if (maybe_slurp(s, "mul", /*only_with_ws=*/true)) {
            read_args_(s);
            return make_command_(Opcode::MUL);
        }

        if (maybe_slurp(s, "zerop", /*only_with_ws=*/true)) {
            read_args_(s);
            return make_command_(Opcode::ZEROP);
        }

        if (maybe_slurp(s, "split", /*only_with_ws=*/true)) {
            read_args_(s);
            return make_command_(Opcode::SPLIT);
        }

        if (maybe_slurp(s, "asplit", /*only_with_ws=*/true)) {
            read_args_(s);
            return make_command_(Opcode::ASPLIT);
        }


        if (maybe_slurp(s, "dload", /*only_with_ws=*/true)) {
            read_args_(s);
            return make_command_(Opcode::DLOAD);
        }

        if (maybe_slurp(s, "div_")) {
            read_inline_input_(s); // width
            read_args_(s);
            return make_command_(Opcode::INT_DIV);
        }

        if (maybe_slurp(s, "div", /*only_with_ws=*/true)) {
            read_args_(s);
            return make_command_(Opcode::FIELD_DIV);
        }

        throw UnexpectedInput(/*found=*/s, /*expected=*/"(command)");
    }
};
