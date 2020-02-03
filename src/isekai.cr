{% unless flag?(:disable_cfront) %}
    require "./frontend_c/parser.cr"
{% end %}
require "./frontend_llvm/parser.cr"
require "./backend/arithfactory"
require "./backend/booleanfactory"
require "./zksnark/libsnark.cr"
require "../lib/libproof/libproof.cr"
require "file_utils"
require "option_parser"
# TODO require "./crystal/ast_dump"

require "./r1cs/r1cs.cr"
require "./r1cs/gate.cr"

require "./backend_alt/arith/board"
require "./backend_alt/arith/req_factory"
require "./backend_alt/arith/backend"
require "./backend_alt/boolean/board"
require "./backend_alt/boolean/req_factory"
require "./backend_alt/boolean/backend"
require "./backend_alt/lay_down_output"
require "./backend_alt/utils"
require "./fmtconv"
require "./zkp_bench.cr"


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
    # bulletproof proof file
    property bullet_file = ""
    # Number of bits in the word - used in the bitwise operations
    # (left shift/right shift/etc) and in calculations/side-effects that
    # are bitwidth-aware - 2nd complement's arithmetic/overflow detection
    # truncation
    property bit_width = 32
    # Print the resulting expressions
    property print_exprs = false
    # Ignore overflow
    property ignore_overflow = false
    # Min width of P in bits
    property p_bits_min = 254
    # Max width of P in bits
    property p_bits_max = 254
    # Force use of primary backend
    property force_primary_backend = false
    # ZKP
    property zkp_scheme = ZKP::Snark
    # Benchmark
    property benchmark = "none"
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

private def run_alt_backend (
        inputs, nizk_inputs, outputs,
        input_values,
        arith_outfile, bool_outfile, options)


    unless arith_outfile.empty?
        File.open(arith_outfile, "w") do |file|
            board = AltBackend::Arith::Board.new(
                inputs,
                nizk_inputs,
                output: file,
                p_bits_min: options.p_bits_min,
                p_bits_max: options.p_bits_max)
            req_factory = AltBackend::Arith::RequestFactory.new(
                board,
                sloppy: options.ignore_overflow)
            backend = AltBackend::Arith::Backend.new(req_factory)
            outputs.each { |expr| AltBackend.lay_down_output(backend, expr) }
            board.done!

        end
        AltBackend.arith_write_inputs(arith_outfile, input_values, inputs, nizk_inputs)
    end

    unless bool_outfile.empty?
        File.open(bool_outfile, "w") do |file|
            board = AltBackend::Boolean::Board.new(
                inputs,
                nizk_inputs,
                output: file)
            req_factory = AltBackend::Boolean::RequestFactory.new(board)
            backend = AltBackend::Boolean::Backend.new(req_factory)
            outputs.each { |expr| AltBackend.lay_down_output(backend, expr) }
            board.done!
        end
        AltBackend.boolean_write_inputs(bool_outfile, input_values, inputs, nizk_inputs)
    end
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
                loop_sanity_limit: options.loop_sanity_limit,
                p_bits_min: options.p_bits_min)
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
                    input_values, arith_outfile, bool_outfile, options)
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

        return input_values.size()  #TODO - We should use the input size coming from the code parsing,
        # because if one provide more input values in the input file, the post-processing will fail while the rest is working fine
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
        OptionParser.parse do |parser|
            parser.banner = "Usage: isekai [arguments] file"
            parser.on("-c", "--cpparg=ARGS", "Extra arguments to clang") { |args| opts.clang_args = args }
            parser.on("-a", "--arith=FILE", "Arithmetic circuit output file") { |file| opts.arith_file = file }
            parser.on("-b", "--bool=FILE", "Boolean circuit output file") { |file| opts.bool_file = file }
            parser.on("-r", "--r1cs=FILE", "R1CS output file") { |file| opts.r1cs_file = file }
            parser.on("-s", "--prove=FILE", "root file name") { |file| opts.root_file = file }
            parser.on("-e", "--scheme=SCHEME", "Zero-Knowledge scheme") { |scheme| opts.zkp_scheme = ZKP.parse(scheme) }
            parser.on("-v", "--verif=FILE", "input file name") { |file| opts.verif_file = file }
            parser.on("-w", "--bit-width=WIDTH", "Width of the word in bits (used for overflow/bitwise operations)") { |width| opts.bit_width = width.to_i() }
            parser.on("-l", "--loop-sanity-limit=LIMIT", "Limit on statically-measured loop unrolling") { |limit| opts.loop_sanity_limit = limit.to_i }
            parser.on("-p", "--progress", "Print progress messages during compilation") { opts.progress = true }
            parser.on("-i", "--ignore-overflow", "Ignore field-P overflows; never truncate") { opts.ignore_overflow = true }
            parser.on("-x", "--print-exprs", "Print output expressions to stdout") { opts.print_exprs = true }
            parser.on("-q", "--p-bits=EXACT|MIN-MAX", "Width of P in bits") do |s|
                if s.includes? '-'
                    opts.p_bits_min, opts.p_bits_max = s.split('-', limit: 2).map &.to_i
                else
                    opts.p_bits_min = opts.p_bits_max = s.to_i
                end
            end
            parser.on("-z", "--primary-backend", "Force use of primary backend") { opts.force_primary_backend = true }
            parser.on("-h", "--help", "Show this help") { puts parser; exit 0 }
            parser.on("-bb", "--bench=SCHEME_LIST", "benchmark zkp libraries") { |bench| opts.benchmark = bench }
        end

        # Filename is passed as the last argument.
        unless ARGV.size() == 1
            puts "There should be exactly one file argument (found #{ARGV.size()})"
            exit 1
        end
        filename = ARGV[-1]

        if (opts.benchmark != "none")
            ZKPBenchmark.new.benchmark(filename, opts.benchmark);
            return
        end

        #snakes
        if opts.verif_file != ""
            #verify
            root_name = opts.verif_file
            case opts.zkp_scheme
            when .dalek?
                result = LibProof.bpVerify( filename, root_name + ".p")
            else ##when .snark? , .libsnark?
                snarc = LibSnark.new()
                result = snarc.verify(root_name + ".s", filename, root_name + ".p")
            end
           
            if result == true
                puts "Congratulations, the proof is correct!\n"
            else
                puts "Incorrect statement\n"
            end

            return
        end

        if opts.root_file != ""
            #proof

            case opts.zkp_scheme
            when .dalek?
                LibProof.bpProve(filename, opts.root_file + ".p");

                #Check the proof
                if LibProof.bpVerify( filename, opts.root_file + ".p")
                    puts "Proved execution successfully with bulletproof, generated:
                        Proof: #{opts.root_file}.p"
                else
                    puts "error generating the proof\n"
                end
            when .snark? , .libsnark?, .groth16?, .bctv14a?
                snarc = LibSnark.new()
                snarc.vcSetup(filename, opts.root_file + ".s", opts.zkp_scheme.value.to_u8)
                snarc.proof(opts.root_file + ".s", filename + ".in", opts.root_file + ".p", opts.zkp_scheme.value.to_u8)

                ##Check the proof:
                if snarc.verify(opts.root_file + ".s", filename + ".in", opts.root_file + ".p")
                    puts "Proved execution successfully with libSnark, generated:
                        Trusted setup : #{opts.root_file}.s
                        Proof: #{opts.root_file}.p"
                else
                    puts "error generating the proof\n"
                end
            when .aurora?, .ligero?, .fractal?
                snarc = LibSnark.new()
                snarc.proof(opts.root_file + ".s", filename, opts.root_file + ".p", opts.zkp_scheme.value.to_u8)
            else
                puts "error invalid scheme\n"
            end

            return
        end

        Log.setup(opts.progress)

        input_file = InputFile.new(filename)
        inputs_nb = -1
        # Generate the arithmetic circuit if arith option is set or r1cs option is set (a temp arith file) and none is provided
        unless input_file.@kind.arith?
            tempArith = ""
            if opts.arith_file != ""
                tempArith = opts.arith_file
            elsif opts.r1cs_file != ""
                tempArith = File.tempfile("arith").path
            end
            inputs_nb = create_circuit(input_file, tempArith, opts.bool_file, opts)
        else
            tempArith = input_file.@filename
        end

        #r1cs
        if opts.r1cs_file != ""
            tempIn = "#{tempArith}.in"
            if File.exists?(tempIn) == false
                puts "inputs file #{tempIn} is missing\n"
            else
                if (opts.zkp_scheme == ZKP::Libsnark_legacy)
                    LibSnarc.generateR1cs(tempArith, tempIn, opts.r1cs_file)
                    #post - processing - only if r1cs is coming from libsnark, when we generate ourself, we already take care of this postprocessing
                    r1 = R1CS.new(opts.bit_width)
                    if (inputs_nb == -1)
                        ##count the number of inputs - we start with -1 because of the 1 constant
                        File.each_line(tempIn) do |line|
                           inputs_nb += 1
                        end
                    end
                    r1.postprocess(opts.r1cs_file + ".in" , inputs_nb)
                else
                    gates : GateKeeper = GateKeeper.new(tempArith, tempIn, opts.r1cs_file, Hash(UInt32,InternalVar).new, opts.zkp_scheme)
                    gates.process_circuit;
                end         
            end
            #clean-up
            if opts.arith_file == "" && input_file.@kind.arith? == false
                FileUtils.rm(tempArith)
            end
        end
    end
end

ParserProgram.new.main()
