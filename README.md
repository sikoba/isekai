[![Build Status](https://api.travis-ci.com/shdown/isekai.svg?branch=develop)](https://travis-ci.com/shdown/isekai)


# isekai in a nutshell

Isekai is a **verifiable computation framework** that allows to work with several programming languages and verifiable computation systems while using a single code-to-circuit module. **Our aim is to make zero-knowledge proofs accessible to mainstream programmers.** Specifically:

* isekai is the *only tool to support 3 ZKP libraries and 5 proof systems*: libsnark (Groth16 and BCTV14a), dalek (Bulletproofs) and libiop (Aurora and Ligero)

* isekai is the *first tool allowing programmers to take existing C or C++ code and generally require only slight modifications to make it compatible with isekai*. This is because isekai supports more features of regular programming languages than any other project we know of, without using a domain specific language.

Isekai is being developed by [Sikoba Research](http://research.sikoba.com) with the support of [Fantom Foundation](http://fantom.foundation). We seek to cooperate with researchers and developers who work on verifiable computation projects, as well as with blockchain projects that want to offer verifiable computation.

To find out more, please consult the [isekai Medium posts](https://medium.com/sikoba-network/isekai/home) or contact us at isekai at protonmail dot com. There is also a (slightly outdated) [isekai Technical documentation](https://github.com/sikoba/isekai/blob/develop/isekai_technical_documentation.pdf) from July 2019.


# Call for sponsors and partners

The initial development of isekai until version 1.0 has been made possible by the support of [Fantom Foundation](http://fantom.foundation). We are now looking for new sponsors and partners for the months ahead. Our goal is to make isekai a community project and to keep it free and open source.
 
# Roadmap

Here is our tentative "to do" list for the coming months.

*Additional language features*:
 - ~~Integer division and modulo~~  &#x2705; DONE (13-DEC-19)!
 - ~~Array look-up and dynamic storage optimisations~~ &#x2705; DONE (13-DEC-19)!
 - Native field operations for efficient cryptgraphic primitives implementation
 - Floating point operations

*LLVM support improvements*:  
- full function call  
- new LLVM instructions: bitcast, memcpy, memset  
- global/static variables  

*Support for additional ZKP systems* :  
- Fractal  
- Plonk  
- Marlin  
- Starks

*LLVM Frontends* : 
- C/C++ (i.e integrating Clang into isekai)  
- Rust  
- Crystal

*More long-term goals*:  
- WebAssembly frontend  
- TinyRAM  
- add FHE library  
- add MPC library  
- python, java frontends
- Domain-specific functions



## Overview

Isekai is a tool for zero-knowledge applications. It currently parses a C/C++ program and outputs the arithmetic and/or boolean circuit representing the expression equivalent to the input program. 
Support for more languages will be added in the future. isekai uses libclang to parse the C program, so most of the preprocessor (including the includes) is available. Then isekai generates an arithmetic representation and converts it to a rank-1 constraints system. 
Isekai can prove and verify the program execution using several ZKP libraries (libsnak, bulletproof and libiop). isekai is written using crystal programming language allowing for a strong type safety and it is compiled to a native executable, ensuring maximum efficiency in parsing.

# isekai 1.0 released! - November 2019

This version is fullfilling our goals for a tool integrating several standard programming languages with several ZKP schemes. 

# Major Update - October 2019

isekai now supports LLVM bitcode! This means in theory that you can compile any language to work with isekai as long as you have an LLVM frontend for it. In practise we have successfully tested C and C++ through LLVM. With the support of LLVM comes many improvements; pointers, arrays, function call and many other C features are supported, and of course, also C++.
Another feature we are proud to deliver is the support of Bulletproof zero-knowledge scheme. One major advantage of this scheme is that proofs do not need a trusted setup. This does not come for free unfortunately as it has impact on performances. Nevertheless, with isekai you can now easily compare with zk-snarks by simply changing the scheme!
We believe isekai is the first project that can handle multiple languages and multiple zero-knowledge proof systems.


# Building the project

## Windows

isekai can be easily tested on Windows using Ubuntu for windows. This [Medium post](https://medium.com/@alexkampa/first-steps-with-isekai-on-windows-e9e5ab2c64d7) indicates how to do it.

## Ubuntu (should work on other Linux distributions)

Start by cloning isekai to a local directory. We recommend to retrieve also the the submodules:

```
$ git clone --recurse-submodules https://github.com/sikoba/isekai.git 	
```

### 1. Install Crystal and required packages

The project is written in Crystal language. Follow the [Official instructions](https://crystal-lang.org/docs/installation/) for instructions how to install Crystal lang. 

Make sure to install the recommended packages, even though only libgmp-dev is actually required for isekai.

Then install the following additional packages required by isekai:

```
$ sudo apt install clang-7
$ sudo apt install libclang-7-dev
$ sudo apt-get install libprocps-dev
$ shards install
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

### 4. Compiling libsnarc

libsnarc is a library which provides a C-wrapper over libsnark and libiop. The library is already included so you do not need to compile it. However, we have noticed errors on some systems, which are fixed by recompiling the library. Please make sure you retrieved the submodules recursively before compiling this library.


```
$ sudo apt-get install libsodium-dev
$ cd lib/libsnarc
$ mkdir build
$ cd build & cmake ..
$ make
```

After having built libsnarc, you need to (re-)build isekai :
```
go to isekai main directory
$ make --always-make
```


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

Basically, you first generates the constraints system with --r1cs option, then with this r1cs you can create a proof using --prove option, and finally verify the proof using the --verif option. The ZKP scheme to use can be specified with the --scheme option.

## LLVM
In order to use LLVM with isekai, you simply provide the LLVM bitcode file instead of the C source code. Please note that LLVM is now the recommended way to use with isekai. The C frontend of isekai will not be maintained but will be probably replaced using the LLVM one.
For instance, use the following commands to use LLVM frontend with C source code:
```
clang -DISEKAI_C_PARSER=0 -O0 -c -emit-llvm my_C_prog.c
./isekai --r1cs=output_file.j1 my_C_prog.bc
```
The inputs should have the .in extension as explained above. In this example it means you should have also the file my_C_prog.bc.in next to my_C_prog.bc
Isekai also generate the assignments in the file output_file.j1.in. It adds ‘.in’ to the filename provided in the r1cs option to get a file for the assignments. Note that existing files are overwritten by isekai.
Isekai automatically uses the inputs provided in my_C_prog.bc.in if it exists. If not, isekai assumes all the inputs are 0.

## Libsnark
To generate (and verify) a proof with libsnark:

```
./isekai --prove=my_snark output_file.j1
```

If the verification pass, this command will generate json files of the proof (my_snark.p) and trusted setup (my_snark.s). Of course in real life, you should not generate a proof and the trusted setup at the same time!

A verifier can verify the proof with the following command:

```
./isekai --verif=my_snark output_file.j1.in
```

A verifier should not know the private inputs (NzikInput) so you should remove the ‘witnesses’ part from the input file before giving it to the verifier.
Two different ZKP schemes from libsnark are supported and can be specified with the --scheme option, refer to the ZKP scheme section below for more information. If the scheme option is not set, it will use libsnark by default.


## Bulletproof

In order to use Bulletproof instead of libsnark, you need to specify the dalek scheme;
```
./isekai --scheme=dalek --r1cs=output_file.j1 my_C_prog.bc
./isekai --scheme=dalek --prove=my_proof output_file.j1
./isekai --verif=my_proof output_file.j1
```
As you can see, the verification requires (for now) the .j1 file (and also the public inputs), contrary to libsnark.
Please note that although very similar, the r1cs generated for libsnark and bulletproof are not compatible, this is why you need to specify the scheme when generating it.

## Features and Limitations

### Programming language
isekai is the most versatile ZKP project that we know of, regarding high-level programming languages supported features:
* full C/C++ pre-processing support
* include files (header files)
* Integer operations:
   * Arithmetic: + , - , * , / , %
   * Binary: and, or, not, xor, left/right shift
   * Comparisons: < , > , <=, >=, ==, !=
* Control flow graphs from C99 code, without goto, break, continue and return statements
* Inline function calls
* Loops with constant (or provided maximum) iterations
* Arrays
* Pointers


### Limitations
However there are still some limitations:
* Function calls must be in-lined
* No support for dynamic pointers, as well as:
  * Dynamic arrays 
  * Dynamic allocations
  * Pointers created from a constant
* Source code must be in one file (except for include files)
* Global/static variables are not supported
* No floating point types
* Entry point must have C name mangling

### ZKP Schemes

With isekai 1.0 we now support more ZKP schemes, the --scheme option can be used with the following values.

| Scheme option     | Type    | 
| :------------- | :----------: |
|  bctv14a  | zk-snark  | 
|  groth16  | zk-snark |
|  dalek  | bulletproof | 
|  ligero  | iop |
|  aurora  | iop | 
