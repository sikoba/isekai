require "option_parser"
require "./parser.cr"
require "./backend/arithfactory"
require "./backend/booleanfactory"
require "file_utils"
require "./zksnark/libsnark.cr"
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

    class ParserProgram

        # C => Arith/Bool circuit
        def create_circuit(in_c_program, out_circuit, options)
            parser = CParser.new(in_c_program,
            options.clang_args,
            options.loop_sanity_limit,
            options.bit_width, options.progress)

            inputs, output = parser.parse()         

            #pp output #add: pp output.state  to print the AST
            in_file = in_c_program + ".in"   #optional file containing the input values to the program
            in_array = [] of Int32
            if File.exists?(in_file)
                File.each_line(in_file) do |line|
                    in_array << line.to_i32 { 0 }
                end
            end
            in_array << 0
            ArithFactory.new(out_circuit, inputs, parser.@nizk_inputs, output, options.bit_width, in_array)
        #    if options.arith_file != ""
         #       ArithFactory.new(options.arith_file, inputs, parser.@nizk_inputs, output, options.bit_width, in_array)
          #  end
           # if options.bool_file != ""
            #    BooleanFactory.new(options.arith_file, inputs, output, options.bit_width)
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
            if ARGV.size() != 1
                puts "There should be exactly one file argument: #{ARGV.size()}"
                #filename = "ex1.c"
                #opts.arith_file = "ex1.ari"
                exit 1
            else 
                filename = ARGV[-1]
            end

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
  
            #circuit
            arith_input = false
            if File.exists?(filename) == false
                puts "file #{filename} is missing\n"
                return
            else
                File.each_line(filename) do |line|
                    if line.starts_with?("total")
                        arith_input = true; #instead of the C program, the input file is an arithmetic circuit
                    end
                    break
                end
            end
            Log.setup(opts.progress)
            #Generate the arithmetic circuit if arith option is set or r1cs option is set (a temp arith file) and none is provided
            if arith_input == false
                tempArith = ""
                if opts.arith_file != ""
                    tempArith = opts.arith_file
                elsif opts.r1cs_file != ""
                    tempArith = File.tempfile("arith").path
                end
                create_circuit(filename, tempArith, opts)
              
            else
                tempArith = filename
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
                if opts.arith_file == "" && arith_input == false
                    FileUtils.rm(tempArith)
                end
            end

          
        end
    end
end
(Isekai::ParserProgram.new).main()
