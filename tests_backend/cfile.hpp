#pragma once

#include <stdio.h>
#include <errno.h>
#include <system_error>

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
