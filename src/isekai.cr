require "option_parser"
require "./parser.cr"
require "./bitcode_parser.cr"
require "./backend/arithfactory"
require "./backend/booleanfactory"
require "file_utils"
#require "./zksnark/libsnark.cr"
# TODO require "./crystal/ast_dump"



module Isekai
    # Structure holding the options passed by the user
    # on the command line
    struct ProgramOptions
        # Additional arguments to pass to libclang (e.g. -I)
        property clang_args = ""
        # Dynamic loop unrolling limit
        property loop_sanity_limit = 1000000
        # Print progress during the execution
        property progress = false
        # Arithmetic circuit output file - the program will output
        # an arithmetic circuit if set
        property arith_file = ""
        # Boolean circuit output file - the program will output
        # an boolean circuit if set
        # an arithmetic circuit if set
        property bool_file = ""
        # R1CS output file - the program will output
        # a r1cs json file if set
        property r1cs_file = ""
        # root name for the generated files for snark proofs. Files will get a suffix 
        property root_file = ""
        # root name for trusted setup and proof (snark)
        property verif_file = ""
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

    class InputFile
        enum Kind
            Arith
            C
            Bitcode
        end

        def initialize (@filename : String)
            @kind =
                if filename.ends_with? ".c"
                    Kind::C
                elsif filename.ends_with? ".bc"
                    Kind::Bitcode
                else
                    Kind::Arith
                end
        end
    end

    class ParserProgram

        def create_circuit (input_file, arith_outfile, bool_outfile, options)
            case input_file.@kind
            when .bitcode?
                parser = BitcodeParser.new(input_file.@filename,
                    options.loop_sanity_limit,
                    options.bit_width)
            when .c?
                parser = CParser.new(input_file.@filename,
                    options.clang_args,
                    options.loop_sanity_limit,
                    options.bit_width, options.progress)
            else
                raise "Unsupported input_file.@kind"
            end

            inputs, nizk_inputs, output = parser.parse()

            # optional file containing the input values to the program
            in_file = input_file.@filename + ".in"
            in_array = [] of Int32
            if File.exists?(in_file)
                File.each_line(in_file) do |line|
                    in_array << line.to_i32 { 0 }
                end
            end
            in_array << 0

            if arith_outfile != ""
                ArithFactory.new(arith_outfile, inputs, nizk_inputs, output, options.bit_width, in_array)
            end
            #if bool_outfile != ""
            #    BooleanFactory.new(bool_outfile, inputs, output, options.bit_width)
            #end
        end

        # Main
        def main
            opts = ProgramOptions.new

           # debugger
           # dump "[1,2,3].each do |e|
           #     puts e
           #   end"

            # Parse the program options. For the detailed
            # explanations refer to struct ProgramOptions
            OptionParser.parse! do |parser|
                parser.banner = "Usage: isekai [arguments] file"
                parser.on("-c", "--cpparg=ARGS", "Extra arguments to clang") { |args| opts.clang_args = args }
                parser.on("-a", "--arith=FILE", "Arithmetic circuit output file") { |file| opts.arith_file = file }
                parser.on("-b", "--bool=FILE", "Boolean circuit output file") { |file| opts.bool_file = file }
                parser.on("-r", "--r1cs=FILE", "R1CS output file") { |file| opts.r1cs_file = file }
                parser.on("-s", "--snark=FILE", "root file name") { |file| opts.root_file = file }
                parser.on("-v", "--verif=FILE", "input file name") { |file| opts.verif_file = file }
                parser.on("-w", "--bit-width", "Width of the word in bits (used for overflow/bitwise operations)") { |width| opts.bit_width = width.to_i() }
                parser.on("-l", "--loop-sanity-limit=LIMIT", "Limit on statically-measured loop unrolling") { |limit| opts.loop_sanity_limit = limit.to_i }
                parser.on("-p", "--progress", "Print progress messages during compilation") { opts.progress = true }
                parser.on("-i", "--ignore-overflow", "Ignore field-P overflows; never truncate") { opts.ignore_overflow = true }
                parser.on("-x", "--print-exprs", "Print output expressions to stdout") { opts.print_exprs = true }
                parser.on("-h", "--help", "Show this help") { puts parser; exit 0 }
            end

            # Filename is passed as the last argument.
            unless ARGV.size() == 1
                puts "There should be exactly one file argument (found #{ARGV.size()})"
                exit 1
            end
            filename = ARGV[-1]

            #snakes
            #if opts.verif_file != ""
            #    #verify
            #    snarc = LibSnark.new()
            #    root_name = opts.verif_file
            #    result = snarc.verify(root_name + ".s", filename, root_name + ".p")
            #    if result == true
            #        puts "Congratulations, the proof is correct!\n"
            #    else
            #        puts "Incorrect statement\n"
            #    end
            #    return
            #end

            #if opts.root_file != ""
            #    #proof
            #    snarc = LibSnark.new()
            #    snarc.vcSetup(filename, opts.root_file + ".s")
            #    snarc.proof(opts.root_file + ".s", filename + ".in", opts.root_file + ".p")

            #    if snarc.verify(opts.root_file + ".s", filename + ".in", opts.root_file + ".p")
            #        puts "Proved execution successfully with libSnark, generated:
            #            Trusted setup : #{opts.root_file}.s
            #            Proof: #{opts.root_file}.p"
            #    else
            #        puts "error generating the proof\n"
            #    end
            #    return
            #end         
  
            Log.setup(opts.progress)

            input_file = InputFile.new(filename)

            # Generate the arithmetic circuit if arith option is set or r1cs option is set (a temp arith file) and none is provided

            unless input_file.@kind.arith?
                tempArith = ""
                if opts.arith_file != ""
                    tempArith = opts.arith_file
                elsif opts.r1cs_file != ""
                    tempArith = File.tempfile("arith").path
                end
                create_circuit(input_file, tempArith, opts.bool_file, opts)
            else
                tempArith = input_file.@filename
            end

            #r1cs
            #if opts.r1cs_file != ""
            #    tempIn = "#{tempArith}.in"
            #    if File.exists?(tempIn) == false
            #        puts "inputs file #{tempIn} is missing\n"
            #    else
            #        LibSnarc.generateR1cs(tempArith, tempIn, opts.r1cs_file)
            #    end
            #    #clean-up
            #    if opts.arith_file == "" && input_file.@kind.arith? == false
            #        FileUtils.rm(tempArith)
            #    end
            #end
        end
    end
end
(Isekai::ParserProgram.new).main()
