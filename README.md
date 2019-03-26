# isekai

Isekai is a **verifiable computation framework** that will allow to work with several programming languages and verifiable computation systems while using a single code-to-circuit module. Isekai is being developed by [Sikoba Research](http://research.sikoba.com) with the support of [Fantom Foundation](http://fantom.foundation). We seek to cooperate with researchers and developers who work on verifiable computation projects, as well as with blockchain projects that want to offer verifiable computation.

To find out more, read our recent (11 Feb 19) [Medium post](https://medium.com/sikoba-network/isekai-verifiable-computation-framework-introduction-and-call-for-partners-daea383b1277) or contact us: isekai at protonmail dot com.

## Description

Isekai is a tool for zero-knowledge applications. It parses a C program and outputs the arithmetic and/or
boolean circuit representing the expression equivalent to the input program.
Isekai uses libclang to parse the C program, so most of the preprocessor
(including the includes) is available. Then isekai uses libsnark to produce a rank-1 constraints system from the arithmetic representation. Isekai can then proove and verify the program execution using libsnark. Isekai is written using crystal
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

#### Note

You may need crystal lang dependencies before running this step:

```
shards update
```


```
docker run --rm -w $PWD -v $PWD:$PWD -ti isekai /bin/bash
```

where you can run `make`, `make test` and run the built binaries.

If you don't want to enter the interactive console, it's enough to
run make within the container:

```
docker run --rm -w $PWD -v $PWD:$PWD isekai make test
```

## Usage
In order to generate an arithmetic representation of a C program, use the following command:

```
./isekai --arith=output_file.arith my_C_prog.c
```

To generate the rank-1 contraints system (r1cs)

```
./isekai --r1cs=output_file.r1 my_C_prog.c
```

You can do both operations at the same time using --r1cs and arith options. To generate (and verify) a proof with libsnark:

```
./isekai --snark=my_snark output_file.r1
```

If the verification pass, this command will generate json files of the proof (my_snark.p) and trusted setup (my_snark.s)
