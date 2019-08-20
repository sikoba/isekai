{% unless flag?(:disable_cfront) %}
    require "./frontend_c/parser.cr"
{% end %}
require "./frontend_llvm/parser.cr"
require "./backend/arithfactory"
require "./backend/booleanfactory"
require "./zksnark/libsnark.cr"
require "file_utils"
require "option_parser"
# TODO require "./crystal/ast_dump"
require "./backend_alt/board"
require "./backend_alt/backend"
require "./backend_alt/utils"
require "./fmtconv"

include Isekai

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
    # Width of P in bits
    property p_bits = 254
    # Force use of primary backend
    property force_primary_backend = false
end

private class InputFile
    enum Kind
        Arith
        C
        Bitcode
    end

    def initialize (@filename : String)
        @kind =
            case filename
            when .ends_with? ".c"
                Kind::C
            when .ends_with? ".bc"
                Kind::Bitcode
            else
                Kind::Arith
            end
    end
end

private def read_input_values (source_filename) : Array(Int32)
    filename = "#{source_filename}.in"
    values = [] of Int32
    if File.exists?(filename)
        File.each_line(filename) do |line|
            values << line.to_i32
        end
    end
    return values
end

private def run_alt_backend (inputs, nizk_inputs, outputs, input_values, arith_outfile, options)
    File.open(arith_outfile, "w") do |file|
        board = AltBackend::Board.new(
            inputs,
            nizk_inputs,
            output: file,
            p_bits: options.p_bits)
        AltBackend::Backend.new(board).lay_down_outputs!(outputs)
    end
    AltBackend::Utils.write_input_values(arith_outfile, input_values, inputs, nizk_inputs)
end

private def run_primary_backend (
        inputs, nizk_inputs, outputs,
        input_values, arith_outfile, bool_outfile, options)

    input_values << 0
    if arith_outfile != ""
        Backend::ArithFactory.new(
            arith_outfile,
            inputs,
            nizk_inputs,
            outputs,
            options.bit_width,
            input_values)
    end
    if bool_outfile != ""
        Backend::BooleanFactory.new(
            bool_outfile,
            inputs,
            outputs,
            options.bit_width)
    end
end

class ParserProgram
    def create_circuit (input_file, arith_outfile, bool_outfile, options)
        input_values = read_input_values(input_file.@filename)
        case input_file.@kind
        when .bitcode?
            parser = LLVMFrontend::Parser.new(
                input_file.@filename,
                loop_sanity_limit: options.loop_sanity_limit)
            inputs, nizk_inputs, outputs = parser.parse()

            if options.print_exprs
                puts outputs
            end

            if options.force_primary_backend
                inputs, nizk_inputs, outputs = FmtConv.new_to_old(inputs, nizk_inputs, outputs)
                run_primary_backend(
                    inputs, nizk_inputs, outputs,
                    input_values, arith_outfile, bool_outfile, options)
            else
                run_alt_backend(
                    inputs, nizk_inputs, outputs,
                    input_values, arith_outfile, options)
            end

        when .c?
            {% unless flag?(:disable_cfront) %}
                parser = CFrontend::Parser.new(
                    input_file.@filename,
                    options.clang_args,
                    options.loop_sanity_limit,
                    options.bit_width,
                    options.progress)
                inputs, nizk_inputs, outputs = parser.parse()

                if options.print_exprs
                    puts outputs
                end

                run_primary_backend(
                    inputs, nizk_inputs, outputs,
                    input_values, arith_outfile, bool_outfile, options)
            {% else %}
                raise "C frontend was disabled at compile time"
            {% end %}
        else
            raise "Unsupported input file extension"
        end
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
            parser.on("-w", "--bit-width=WIDTH", "Width of the word in bits (used for overflow/bitwise operations)") { |width| opts.bit_width = width.to_i() }
            parser.on("-l", "--loop-sanity-limit=LIMIT", "Limit on statically-measured loop unrolling") { |limit| opts.loop_sanity_limit = limit.to_i }
            parser.on("-p", "--progress", "Print progress messages during compilation") { opts.progress = true }
            parser.on("-i", "--ignore-overflow", "Ignore field-P overflows; never truncate") { opts.ignore_overflow = true }
            parser.on("-x", "--print-exprs", "Print output expressions to stdout") { opts.print_exprs = true }
            parser.on("-q", "--p-bits=BITS", "Width of P in bits") { |bits| opts.p_bits = bits.to_i() }
            parser.on("-z", "--primary-backend", "Force use of primary backend") { opts.force_primary_backend = true }
            parser.on("-h", "--help", "Show this help") { puts parser; exit 0 }
        end

        # Filename is passed as the last argument.
        unless ARGV.size() == 1
            puts "There should be exactly one file argument (found #{ARGV.size()})"
            exit 1
        end
        filename = ARGV[-1]

        #snakes
        if opts.verif_file != ""
            #verify
            snarc = LibSnark.new()
            root_name = opts.verif_file
            result = snarc.verify(root_name + ".s", filename, root_name + ".p")
            if result == true
                puts "Congratulations, the proof is correct!\n"
            else
                puts "Incorrect statement\n"
            end
            return
        end

        if opts.root_file != ""
            #proof
            snarc = LibSnark.new()
            snarc.vcSetup(filename, opts.root_file + ".s")
            snarc.proof(opts.root_file + ".s", filename + ".in", opts.root_file + ".p")

            if snarc.verify(opts.root_file + ".s", filename + ".in", opts.root_file + ".p")
                puts "Proved execution successfully with libSnark, generated:
                    Trusted setup : #{opts.root_file}.s
                    Proof: #{opts.root_file}.p"
            else
                puts "error generating the proof\n"
            end
            return
        end

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
        if opts.r1cs_file != ""
            tempIn = "#{tempArith}.in"
            if File.exists?(tempIn) == false
                puts "inputs file #{tempIn} is missing\n"
            else
                LibSnarc.generateR1cs(tempArith, tempIn, opts.r1cs_file)
            end
            #clean-up
            if opts.arith_file == "" && input_file.@kind.arith? == false
                FileUtils.rm(tempArith)
            end
        end
    end
end

ParserProgram.new.main()
