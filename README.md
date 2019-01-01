# isekai
Isekai verifiable computation project

## Description

Isekai is a tool which parses the C program and outputs the arithmetic and/or
boolean circuit representing the expression equivalent to the input program.
Isekai uses libclang to parse the C program, so most of the preprocessor
(including the includes) is available. Isekai is written using crystal
programming language allowing for a strong type safety and it is compiled to a
native executable, ensuring maximum efficiency in parsing.

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
to install Crystal lang. 

Since the project depends on several libclang patches which are not
yet merged in the libclang (https://www.mail-archive.com/cfe-commits@cs.uiuc.edu/msg95414.html,
http://lists.llvm.org/pipermail/cfe-commits/Week-of-Mon-20140428/104048.html), the easiest
is to use the provided pre-build binary and to build and run the software inside
a container.

### Installing docker

To install docker on Ubuntu, follow the [official instructions](https://docs.docker.com/install/linux/docker-ce/ubuntu/)

### Building and running inside docker container

To build a docker image with the `isekai` tag, enter `docker` directory and run `make image`.
This will build `isekai` image which then you can use to spawn a container and mount
the main directory:

```
docker run -w $PWD -v $PWD:$PWD -ti isekai /bin/bash
```

where you can run `make`, `make test` and run the built binaries.

If you don't want to enter the interactive console, it's enough to
run make within the container:

```
docker run -w $PWD -v $PWD:$PWD isekai make test
```
