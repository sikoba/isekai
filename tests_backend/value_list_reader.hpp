#pragma once

#include "cfile.hpp"
#include <stdio.h>
#include <exception>

class ValueListReader
{
    CFile file_;
    char buf_[128];
    unsigned next_index_ = 0;

    struct Value
    {
        bool ok;
        const char *hex;

        operator bool() const { return ok; }
    };

    struct UnexpectedIndex : public std::exception
    {
        const char *what() const noexcept override
        {
            return "unexpected index";
        }
    };

public:
    ValueListReader(const char *path) : file_(path, "r") {}

    ValueListReader(const std::string &path) : ValueListReader(path.c_str()) {}

    Value next_value()
    {
        unsigned i;
        if (fscanf(file_, "%u %127s", &i, buf_) != 2) {
            return Value{false, nullptr};
        }
        if (i != next_index_) {
            throw UnexpectedIndex{};
        }
        ++next_index_;
        return Value{true, buf_};
    }
};
