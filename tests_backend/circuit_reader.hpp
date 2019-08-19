#pragma once

#include "cfile.hpp"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <vector>
#include <exception>

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
        const char *inline_hex;
        bool ok;

        operator bool() const { return ok; }

        static Command invalid()
        {
            Command res;
            res.ok = false;
            return res;
        }
    };

    class UnexpectedInput : public std::exception
    {
        std::string what_;
    public:
        UnexpectedInput(const char *found, const char *expected)
            : what_("Found: '")
        {
            size_t nfound = strlen(found);
            while (nfound && found[nfound - 1] == '\n') {
                --nfound;
            }
            what_.append(found, nfound).append("', expected: ").append(expected);
        }

        UnexpectedInput(const char *msg) : what_(msg) {}

        const char *what() const noexcept override { return what_.c_str(); }
    };

    CFile file_;
    char *buf_ = nullptr;
    size_t nbuf_ = 0;
    char *inline_hex_ = nullptr;
    std::vector<unsigned> inputs_buf_;
    std::vector<unsigned> outputs_buf_;

    static char * try_slurp_(char *s, const char *prefix)
    {
        const size_t nprefix = strlen(prefix);
        return strncmp(s, prefix, nprefix) == 0 ? s + nprefix : nullptr;
    }

    static void slurp_(char *&s, const char *prefix)
    {
        if (!(s = try_slurp_(s, prefix))) {
            throw UnexpectedInput(s, prefix);
        }
    }

    static void skip_ws_(char *&s)
    {
        while (*s == ' ') {
            ++s;
        }
    }

    static void parse_int_(char *&s, unsigned &out)
    {
        out = 0;
        int ndigits = 0;
        for (;; ++s, ++ndigits) {
            const int digit = ((int) *s) - '0';
            if (digit < 0 || digit > 9) {
                break;
            }
            out = out * 10 + digit;
        }
        if (!ndigits) {
            throw UnexpectedInput(s, "(digit)");
        }
    }

    void handle_inline_hex_(char *&s)
    {
        inline_hex_ = s;
        while (((unsigned char) *s) > 32) {
            ++s;
        }
        if (*s != ' ') {
            throw UnexpectedInput(s, "(space)");
        }
        *s = '\0';
        ++s;
    }

    void reset_()
    {
        inputs_buf_.clear();
        outputs_buf_.clear();
        inline_hex_ = nullptr;
    }

    void read_inline_input_(char *s)
    {
        skip_ws_(s);
        unsigned u;
        parse_int_(s, u);
        inputs_buf_.push_back(u);
    }

    void read_args_part_(char *&s, const char *keyword, std::vector<unsigned> &out)
    {
        skip_ws_(s);
        slurp_(s, keyword);

        skip_ws_(s);
        unsigned nargs;
        parse_int_(s, nargs);

        skip_ws_(s);
        slurp_(s, "<");

        out.reserve(nargs);
        for (unsigned i = 0; i < nargs; ++i) {
            skip_ws_(s);
            unsigned u;
            parse_int_(s, u);
            out.push_back(u);
        }

        skip_ws_(s);
        slurp_(s, ">");
    }

    void read_args_(char *s)
    {
        read_args_part_(s, "in ", inputs_buf_);
        read_args_part_(s, "out ", outputs_buf_);
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
        return getline(&buf_, &nbuf_, file_) > 0;
    }

    bool should_skip_line_()
    {
        return buf_[0] == '#';
    }

public:
    CircuitReader(const char *path) : file_(path, "r") {}

    CircuitReader(const std::string &path) : CircuitReader(path.c_str()) {}

    size_t total()
    {
        do {
            if (!read_line_()) {
                throw UnexpectedInput("error or EOF before 'total' line");
            }
        } while (should_skip_line_());

        char *s = buf_;
        slurp_(s, "total ");
        skip_ws_(s);
        unsigned u;
        parse_int_(s, u);
        return u;
    }

    Command next_command()
    {
        reset_();

        do {
            if (!read_line_()) {
                return Command::invalid();
            }
        } while (should_skip_line_());

        char *v;

        if ((v = try_slurp_(buf_, "input "))) {
            read_inline_input_(v);
            return make_command_(Opcode::INPUT);
        }

        if ((v = try_slurp_(buf_, "nizkinput "))) {
            read_inline_input_(v);
            return make_command_(Opcode::NIZK_INPUT);
        }

        if ((v = try_slurp_(buf_, "output "))) {
            read_inline_input_(v);
            return make_command_(Opcode::OUTPUT);
        }

        if ((v = try_slurp_(buf_, "const-mul-neg-"))) {
            handle_inline_hex_(v);
            read_args_(v);
            return make_command_(Opcode::CONST_MUL_NEG);
        }

        if ((v = try_slurp_(buf_, "const-mul-"))) {
            handle_inline_hex_(v);
            read_args_(v);
            return make_command_(Opcode::CONST_MUL);
        }

        if ((v = try_slurp_(buf_, "add "))) {
            read_args_(v);
            return make_command_(Opcode::ADD);
        }

        if ((v = try_slurp_(buf_, "mul "))) {
            read_args_(v);
            return make_command_(Opcode::MUL);
        }

        if ((v = try_slurp_(buf_, "zerop "))) {
            read_args_(v);
            return make_command_(Opcode::ZEROP);
        }

        if ((v = try_slurp_(buf_, "split "))) {
            read_args_(v);
            return make_command_(Opcode::SPLIT);
        }

        throw UnexpectedInput(buf_, "(command)");
    }

    ~CircuitReader()
    {
        free(buf_);
    }
};
