# isekai

Isekai is a **verifiable computation framework** that will allow to work with several programming languages and verifiable computation systems while using a single code-to-circuit module. Isekai is being developed by [Sikoba Research](http://research.sikoba.com) with the support of [Fantom Foundation](http://fantom.foundation). We seek to cooperate with researchers and developers who work on verifiable computation projects, as well as with blockchain projects that want to offer verifiable computation.

To find out more, please consult the **[isekai Technical documentation](https://github.com/sikoba/isekai/blob/develop/isekai_technical_documentation.pdf)**, read this [Medium post](https://medium.com/sikoba-network/isekai-verifiable-computation-framework-introduction-and-call-for-partners-daea383b1277) or contact us: isekai at protonmail dot com.




## Overview

Isekai is a tool for zero-knowledge applications. It currently parses a C program and outputs the arithmetic and/or boolean circuit representing the expression equivalent to the input program. Support for more languages will be added in the future. Isekai uses libclang to parse the C program, so most of the preprocessor (including the includes) is available. Then isekai uses libsnark to produce a rank-1 constraints system from the arithmetic representation. Isekai can then proove and verify the program execution using libsnark. Isekai is written using crystal programming language allowing for a strong type safety and it is compiled to a native executable, ensuring maximum efficiency in parsing.


# Building the project

## Windows

isekai can be easily tested on Windows using Ubuntu for windows. This [Medium post](https://medium.com/@alexkampa/first-steps-with-isekai-on-windows-e9e5ab2c64d7) indicates how to do it.

## Ubuntu (should work on other Linux distributions)

Start by cloning isekai to a local directory.

### 1. Install Crystal and required packages

The project is written in Crystal language. Follow the [Official instructions](https://crystal-lang.org/docs/installation/) for instructions how to install Crystal lang. 

Make sure to install the recommended packages, even though only libgmp-dev is actually required for isekai.

Then install the following additional packages required by isekai:

```
$ sudo apt install clang-7
$ sudo apt install libclang-7-dev
$ sudo apt-get install libprocps-dev
```
### 2. Apply libclang patch

The project depends on several libclang patches which are not yet merged in the libclang (https://www.mail-archive.com/cfe-commits@cs.uiuc.edu/msg95414.html,
http://lists.llvm.org/pipermail/cfe-commits/Week-of-Mon-20140428/104048.html)

Applying the patch is done from the docker subdirectory:


```
$ cd docker/
$ cp bin/libclang.so.gz /tmp/libclang.so.gz
$ gzip -d /tmp/libclang.so.gz
$ sudo cp /tmp/libclang.so /usr/lib/x86_64-linux-gnu/libclang-7.so.1
$ sudo cp /tmp/libclang.so /usr/lib/libclang.so.7
$ cd ..
```

### 3. Install isekai

The project comes with the Makefile and in order to compile the project, running `make` will be enough. That will create the `isekai` binary file in the current directory. To run tests `make test` should be used.

Alternatively, `crystal build src/isekai.cr` or `crystal test` can be used.


```
$ make
$ make test
```

The result of `make test` should end with something resembling this:

```
...
Finished in 800.85 milliseconds
9 examples, 0 failures, 0 errors, 0 pending
```


## Docker

The docker files included with the project are not up to date and should not be used. 


## Usage

(Also check the "Some tests with isekai" section of the above-mentioned [Medium post](https://medium.com/@alexkampa/first-steps-with-isekai-on-windows-e9e5ab2c64d7))

Isekai can generate a proof of the execution of a C function. 
The C function must have one of the following signature:
```
void outsource(struct Input *input, struct NzikInput * nzik, struct Output *output);
void outsource(struct Input *input, struct Output *output);
void outsource(struct NzikInput * nzik, struct Output *output);
```
Input and Output are public parameters and NzikInput are the private parameters (zero-knowledge). Inputs and NzikInputs can be provided in an additional file, by putting each value one per line. This input file must have the same name as the C program file, with an additional ‘.in’ extension. For instance, if the function is implemented in my_C_prog.c, the inputs must be provided in my_C_prog.c.in

In order to generate an arithmetic representation of a C program, use the following command:

```
./isekai --arith=output_file.arith my_C_prog.c
```

To generate the rank-1 contraints system (r1cs)

```
./isekai --r1cs=output_file.j1 my_C_prog.c
```
You can do both operations at the same time using --r1cs and arith options. 
Isekai also generate the assignments in the file output_file.j1.in. It adds ‘.in’ to the filename provided in the r1cs option to get a file for the assignments. Note that existing files are overwritten by isekai.
Isekai automatically uses the inputs provided in my_C_prog.c.in if it exists. If not, isekai assumes all the inputs are 0.


To generate (and verify) a proof with libsnark:

```
./isekai --snark=my_snark output_file.j1
```

If the verification pass, this command will generate json files of the proof (my_snark.p) and trusted setup (my_snark.s). Of course in real life, you should not generate a proof and the trusted setup at the same time!

A verifier can verify the proof with the following command:

```
./isekai --verif=my_snark output_file.j1.in
```

A verifier should not know the private inputs (NzikInput) so you should remove the ‘witnesses’ part from the input file before giving it to the verifier.
