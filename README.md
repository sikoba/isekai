# isekai
Isekai verifiable computation project

# Building the project

## Compiling

The project comes with the Makefile and in order to compile the
project, running `make` will be enough. That will create `isekai`
binary file in the current directory. To run tests `make test`
should be used.

Alternatively, `crystal build src/isekai.cr` or `crystal test`
can be used.

## Dependencies

The project is written in Crystal language. Follow the [Official
instructions](https://crystal-lang.org/docs/installation/) for instructions how
to install Crystal lang. The only library dependency is `libclang` library. On
Ubuntu it can be installed via `sudo apt install libclang1-6.0 clang-6.0`

### Installing libclang on Debian 9

To install libclang on Debian 9, the steps are:

1. Add https://apt.llvm.org/'s repo as listed
2. apt install clang-6.0-dev
