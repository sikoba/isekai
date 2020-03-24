#pragma once

#include "nagai.h"

class Field
{
    Nagai *ptr_;

    __attribute__((always_inline))
    explicit Field(Nagai *ptr) noexcept
        : ptr_{ptr}
    {}

public:
    // Note that this transfers the ownership of 'ptr' to the created instance.
    __attribute__((always_inline))
    static Field slurp(Nagai *ptr) noexcept
    {
        return Field{ptr};
    }

    __attribute__((always_inline))
    static Field copy_from(Nagai *ptr) noexcept
    {
        return Field{nagai_copy(ptr)};
    }

    __attribute__((always_inline))
    Field(uint64_t value = 0, bool negative = false) noexcept
        : ptr_{negative ? nagai_init_neg(value) : nagai_init_pos(value)}
    {}

    __attribute__((always_inline))
    explicit Field(const char *s) noexcept
        : ptr_{nagai_init_from_str(s)}
    {}

    __attribute__((always_inline))
    Field(const Field &that) noexcept
        : ptr_{nagai_copy(that.ptr_)}
    {}

    __attribute__((always_inline))
    Field& operator =(const Field &that) noexcept
    {
        Nagai *tmp = nagai_copy(that.ptr_);
        nagai_free(ptr_);
        ptr_ = tmp;
        return *this;
    }   

    __attribute__((always_inline))
    Field operator +(const Field &that) const noexcept
    {
        return Field{nagai_add(ptr_, that.ptr_)};
    }

    __attribute__((always_inline))
    Field operator -(const Field &that) const noexcept
    {
        return Field{nagai_sub(ptr_, that.ptr_)};
    }

     __attribute__((always_inline))
    Field operator -() const noexcept
    {
        return *this * Field(/*value=*/1, /*negative=*/true);
    }

    __attribute__((always_inline))
    Field operator *(const Field &that) const noexcept
    {
        return Field{nagai_mul(ptr_, that.ptr_)};
    }

    __attribute__((always_inline))
    Field operator ~() const noexcept
    {
        return Field{nagai_inv(ptr_)};
    }

    __attribute__((always_inline))
    Field operator /(const Field &that) const noexcept
    {
        return Field{nagai_div(ptr_, that.ptr_)};
    }

    __attribute__((always_inline))
    Field bit_at(uint64_t pos) const noexcept
    {
        return Field{nagai_getbit(ptr_, pos)};
    }

    __attribute__((always_inline))
    Field raise_to(const Field &that, unsigned limit) const noexcept
    {
        return Field{nagai_exp(ptr_, that.ptr_, limit)};
    }

    __attribute__((always_inline))
    Field& operator +=(const Field &that) noexcept
    {
        return *this = *this + that;
    }

    __attribute__((always_inline))
    Field& operator -=(const Field &that) noexcept
    {
        return *this = *this - that;
    }

    __attribute__((always_inline))
    Field& operator *=(const Field &that) noexcept
    {
        return *this = *this * that;
    }

    __attribute__((always_inline))
    Field& operator /=(const Field &that) noexcept
    {
        return *this = *this / that;
    }

    __attribute__((always_inline))
    explicit operator bool () const noexcept
    {
        return nagai_nonzero(ptr_);
    }

    __attribute__((always_inline))
    bool operator ==(const Field &that) noexcept
    {
        return !static_cast<bool>(*this - that);
    }

    __attribute__((always_inline))
    bool operator !=(const Field &that) noexcept
    {
        return static_cast<bool>(*this - that);
    }

    __attribute__((always_inline))
    explicit operator uint64_t () const noexcept
    {
        return nagai_lowbits(ptr_);
    }

    __attribute__((always_inline))
    explicit operator Nagai * () const noexcept
    {
        return ptr_;
    }

    __attribute__((always_inline))
    Nagai *release() const noexcept
    {
        return nagai_copy(ptr_);
    }

    __attribute__((always_inline))
    ~Field() noexcept
    {
        nagai_free(ptr_);
    }
};
