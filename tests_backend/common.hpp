#pragma once

#include <exception>

struct ParseUIntError : public std::exception
{
    const char * what() const noexcept override
    {
        return "cannot parse integer";
    }
};

struct BaseDec
{
    static int parse(char c)
    {
        return static_cast<int>(c) - '0';
    }

    static bool is_invalid(int digit)
    {
        return digit < 0 || digit > 9;
    }

    static const int radix = 10;
};

struct BaseHex
{
    static int parse(char c)
    {
        if ('0' <= c && c <= '9') {
            return c - '0';
        }
        if ('a' <= c && c <= 'f') {
            return c - 'a' + 10;
        }
        if ('A' <= c && c <= 'F') {
            return c - 'A' + 10;
        }
        return -1;
    }

    static bool is_invalid(int digit)
    {
        return digit < 0;
    }

    static const int radix = 16;
};

template<class T, class Iterator, class Base>
static void parse_uint(Iterator &it, T &out, Base)
{
    out = 0;
    int ndigits = 0;
    for (;; ++it, ++ndigits) {
        const auto digit = Base::parse(*it);
        if (Base::is_invalid(digit)) {
            break;
        }
        out *= Base::radix;
        out += digit;
    }
    if (!ndigits) {
        throw ParseUIntError{};
    }
}

template<class T, class Iterator, class Base>
static void parse_uint_until_nul(Iterator it, T &out, Base base)
{
    parse_uint(it, out, base);
    if (*it != '\0') {
        throw ParseUIntError{};
    }
}
