#pragma once

#include <system_error>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <assert.h>

class CFile
{
    FILE *file_;
public:
    CFile(const char *path, const char *mode)
    {
        if (!(file_ = fopen(path, mode))) {
            const int saved_errno = errno;
            throw std::system_error(saved_errno, std::generic_category(), path);
        }
    }

    CFile(const CFile &) = delete;

    CFile(CFile &&other) : file_{other.file_}
    {
        other.file_ = nullptr;
    }

    CFile & operator =(const CFile &) = delete;

    CFile & operator =(CFile &&other)
    {
        file_ = other.file_;
        other.file_ = nullptr;
        return *this;
    }

    operator FILE * () { return file_; }

    ~CFile()
    {
        if (file_) {
            fclose(file_);
        }
    }
};

class CFileLine
{
    char *buf_;
    size_t nbuf_;
public:
    CFileLine() : buf_{nullptr}, nbuf_{0} {}
    explicit CFileLine(size_t prealloc) : buf_{nullptr}, nbuf_{prealloc} {}

    CFileLine(const CFileLine &) = delete;

    CFileLine(CFileLine &&other) : buf_{other.buf_}, nbuf_{other.nbuf_}
    {
        other.buf_ = nullptr;
    }

    CFileLine& operator =(const CFileLine &) = delete;

    CFileLine& operator =(CFileLine &&other)
    {
        buf_ = other.buf_;
        nbuf_ = other.nbuf_;
        other.buf_ = nullptr;
        return *this;
    }

    ssize_t read_from(FILE *f)
    {
        return getline(&buf_, &nbuf_, f);
    }

    char * c_str()
    {
        assert(buf_ && nbuf_);
        return buf_;
    }

    ~CFileLine() { free(buf_); }
};
