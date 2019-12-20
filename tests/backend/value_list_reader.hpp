#pragma once

#include "cfile.hpp"
#include "common.hpp"
#include <string>
#include <stdio.h>

class ValueListReader
{
    CFile file_;
    CFileLine line_;
    unsigned next_index_ = 0;

    struct Value
    {
        bool ok;
        char *hex;

        operator bool() const { return ok; }
    };

public:
    explicit ValueListReader(const char *path) : file_(path, "r") {}

    explicit ValueListReader(const std::string &path) : ValueListReader(path.c_str()) {}

    Value next_value()
    {
        if (line_.read_from(file_) <= 0)
            return Value{false, nullptr};

        char *s = line_.c_str();

        unsigned index;
        slurp_uint(s, index, /*base=*/10);

        if (index != next_index_)
            throw UnexpectedInput("unexpected index");
        ++next_index_;

        slurp_some_ws(s);

        char *hex_start = s;
        slurp_any_printable(s);
        *s = '\0';

        return Value{true, hex_start};
    }
};
