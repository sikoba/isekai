#pragma once

#include "cfile.hpp"
#include "common.hpp"
#include <string>
#include <exception>
#include <stdio.h>

class ValueListReader
{
    CFile file_;
    CFileLine line_;
    unsigned next_index_ = 0;

    struct Value
    {
        bool ok;
        const char *hex;

        operator bool() const { return ok; }
    };

    class UnexpectedInput : public std::exception
    {
        std::string what_;
    public:
        explicit UnexpectedInput(const std::string &what) : what_(what) {}

        const char *what() const noexcept override
        {
            return what_.c_str();
        }
    };

public:
    explicit ValueListReader(const char *path) : file_(path, "r") {}

    explicit ValueListReader(const std::string &path) : ValueListReader(path.c_str()) {}

    Value next_value()
    {
        if (line_.read_from(file_) <= 0) {
            return Value{false, nullptr};
        }
        char *s = line_.c_str();

        unsigned index;
        parse_uint(s, index, BaseDec{});
        if (index != next_index_) {
            throw UnexpectedInput("unexpected index");
        }
        ++next_index_;

        if (*s != ' ') {
            throw UnexpectedInput("no space after index");
        }
        do {
            ++s;
        } while (*s == ' ');

        char *hex_start = s;
        while (static_cast<unsigned char>(*s) > 32) {
            ++s;
        }
        *s = '\0';

        return Value{true, hex_start};
    }
};
