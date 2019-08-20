utils_CLANG=( clang )
utils_NATIVE_CC=( clang -O0 -Wall -Wextra -fsanitize=undefined )
utils_ISEKAI=( ../isekai )
utils_BOILERPLATE_GEN=( ../boilerplate_gen )
utils_JUDGE=( ./judge )
utils_RNG=( ./rng )

utils_TEMP_DIR=./cruft

utils_BC_FILE=$utils_TEMP_DIR/bitcode.bc
utils_ARCI_FOR_BC_FILE=$utils_TEMP_DIR/arith_bc.arci
utils_ARCI_FOR_C_FILE=$utils_TEMP_DIR/arith_c.arci
utils_PREPROCD_C_FILE=$utils_TEMP_DIR/preprocd_src.c
utils_NATIVE_BIN=$utils_TEMP_DIR/native_bin
utils_JUDGE_OUTPUT=$utils_TEMP_DIR/out_judge.txt
utils_NATIVE_OUTPUT=$utils_TEMP_DIR/out_native.txt
utils_RNG_OUTPUT=$utils_TEMP_DIR/random.in

utils__stress_nlines=-1

# $1: file path, possibly relative
# $2: working directory
#
# Prints out the result to stdout.
utils_resolve_relative() {
    case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s\n' "$2/$1" ;;
    esac
}

# $@: command and arguments
utils_trace_run() {
    printf >&2 '≈≈≈≈≈≈> %s\n' "$*"
    "$@"
}

# $1: C source file
utils_compile_c_to_bc() {
    utils_trace_run \
        "${utils_CLANG[@]}" \
        -DISEKAI_C_PARSER=0 \
        -O0 -c -emit-llvm \
        "$1" \
        -o "$utils_BC_FILE" || return $?
}

# $1: C source file
utils_preprocess_for_c_parser() {
    utils_trace_run \
        "${utils_CLANG[@]}" \
        -E \
        -DISEKAI_C_PARSER=1 \
        "$1" \
        -o "$utils_PREPROCD_C_FILE" || return $?
    # Remove preprocessor "comments"
    sed '/^#/d' -i -- "$utils_PREPROCD_C_FILE" || return $?
}

# $@: isekai arguments (optional)
utils_run_c_parser() {
    utils_trace_run \
        "${utils_ISEKAI[@]}" \
        --arith="$utils_ARCI_FOR_C_FILE" \
        "$@" \
        "$utils_PREPROCD_C_FILE" || return $?
}

# $@: isekai arguments (optional)
utils_run_bc_parser() {
    utils_trace_run \
        "${utils_ISEKAI[@]}" \
        --arith="$utils_ARCI_FOR_BC_FILE" \
        "$@" \
        "$utils_BC_FILE" || return $?
}

# $1: C source file
utils_compile_c_to_native() {
    {
        cat -- "$1"
        utils_trace_run "${utils_BOILERPLATE_GEN[@]}" "$1"
    } | utils_trace_run "${utils_NATIVE_CC[@]}" -x c - -o "$utils_NATIVE_BIN"
    local -a statuses=( "${PIPESTATUS[@]}" )

    local s
    for s in "${statuses[@]}"; do
        if (( s != 0 )); then
            return $s
        fi
    done
    return 0
}

# $1: file 1
# $2: file 2
utils_check_files_equal() {
    # TODO: color support
    if cmp -- "$1" "$2"; then
        echo >&2 '[OK] FILES ARE EQUAL'
    else
        echo >&2 '[ERROR] FILES DIFFER!'
        echo >&2
        utils_trace_run diff -u -- "$1" "$2" || true
        return 1
    fi
}

# $1: C source file
utils_test_case_prepare() {
    utils_compile_c_to_bc "$1" || return $?
    utils_compile_c_to_native "$1" || return $?
}

# $1: file with input values
# $2: output bit width
# $3...$#: isekai arguments (optional)
utils_test_case_run() {
    local in=$1; shift
    local bitwidth=$1; shift
    utils_trace_run cp -- "$in" "$utils_BC_FILE".in || return $?
    utils_run_bc_parser "$@" || return $?
    local board=$utils_ARCI_FOR_BC_FILE
    local board_in="$board".in
    utils_trace_run "${utils_JUDGE[@]}" -w "$bitwidth" "$board" > "$utils_JUDGE_OUTPUT" || return $?
    utils_trace_run "$utils_NATIVE_BIN" < "$board_in" > "$utils_NATIVE_OUTPUT" || return $?
    utils_check_files_equal "$utils_JUDGE_OUTPUT" "$utils_NATIVE_OUTPUT" || return $?
}

# $1: test case directory
utils_stress_test_can_run() {
    if grep -q '^defined_on_whole_range\s*=\s*true' -- "$1"/test_props.ini; then
        return 0
    else
        return 1
    fi
}

# $1: test case directory
utils_stress_test_prepare() {
    utils_test_case_prepare "$1"/prog.c
    local -a in_files=( "$1"/*.in )
    utils__stress_nlines=$(wc -l < "${in_files[0]}") || return $?
}

# $1: output bit width
# $2...$#: isekai arguments (optional)
utils_stress_test_run_once() {
    utils_trace_run "${utils_RNG[@]}" "$utils__stress_nlines" > "$utils_RNG_OUTPUT" || return $?
    utils_test_case_run "$utils_RNG_OUTPUT" "$@" || return $?
}

# no arguments
utils_cleanup() {
    local file
    for file in \
        "$utils_BC_FILE" \
        "$utils_ARCI_FOR_BC_FILE" \
        "$utils_ARCI_FOR_C_FILE" \
        "$utils_PREPROCD_C_FILE"
    do
        rm -f -- "$file" "$file".in
    done
    rm -f -- "$utils_NATIVE_BIN" "$utils_JUDGE_OUTPUT" "$utils_NATIVE_OUTPUT" "$utils_RNG_OUTPUT"
}
