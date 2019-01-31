require "option_parser"
require "./parser.cr"
require "./backend/arithfactory"
require "./backend/booleanfactory"

module Isekai
    # Structure holding the options passed by the user
    # on the command line
    struct ProgramOptions
        # Additional arguments to pass to libclang (e.g. -I)
        property clang_args = ""
        # Dynamic loop unrolling limit
        property loop_sanity_limit = 0
        # Print progress during the execution
        property progress = false
        # Arithmetic circuit output file - the program will output
        # an arithmetic circuit if set
        property arith_file = ""
        # Boolean circuit output file - the program will output
        # an boolean circuit if set
        # an arithmetic circuit if set
        property bool_file = ""
        # Number of bits in the word - used in the bitwise operations
        # (left shift/right shift/etc) and in calculations/side-effects that
        # are bitwidth-aware - 2nd complement's arithmetic/overflow detection
        # truncation
        property bit_width = 32
        # Print the resulting expressions
        property print_exprs = false
        # Ignore overflow
        property ignore_overflow = false
    end

    class ParserProgram
        # Main 
        def main
            opts = ProgramOptions.new

            # Parse the program options. For the detailed
            # explanations refer to struct ProgramOptions
            OptionParser.parse! do |parser|
                parser.banner = "Usage: isekai [arguments] file"
                parser.on("-c", "--cpparg=ARGS", "Extra arguments to clang") { |args| opts.clang_args = args }
                parser.on("-a", "--arith=FILE", "Arithmetic circuit output file") { |file| opts.arith_file = file }
                parser.on("-b", "--bool=FILE", "Boolean circuit output file") { |file| opts.bool_file = file }
                parser.on("-w", "--bit-width", "Width of the word in bits (used for overflow/bitwise operations)") { |width| opts.bit_width = width.to_i() }
                parser.on("-l", "--loop-sanity-limit=LIMIT", "Limit on statically-measured loop unrolling") { |limit| opts.loop_sanity_limit = limit.to_i }
                parser.on("-p", "--progress", "Print progress messages during compilation") { opts.progress = true }
                parser.on("-i", "--ignore-overflow", "Ignore field-P overflows; never truncate") { opts.ignore_overflow = true }
                parser.on("-x", "--print-exprs", "Print output expressions to stdout") { opts.print_exprs = true }
                parser.on("-h", "--help", "Show this help") { puts parser; exit 0 }
            end

            # Filename is passed as the last argument.
            if ARGV.size() != 1
                puts "There should be exactly one file argument"
                exit 1
            end

            filename = ARGV[-1]

            Log.setup(opts.progress)
            parser = CParser.new(filename,
                                 opts.clang_args,
                                 opts.loop_sanity_limit,
                                 opts.bit_width, opts.progress)

            inputs, output = parser.parse()

            

            if opts.arith_file
                ArithFactory.new(opts.arith_file, inputs, parser.@nizk_inputs, output, opts.bit_width)
            end

            if opts.arith_file
                BooleanFactory.new(opts.arith_file, inputs, output, opts.bit_width)
            end
        end
    end
end
(Isekai::ParserProgram.new).main()
