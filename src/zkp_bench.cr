require "./zksnark/libsnark.cr"
require "../lib/libproof/libproof.cr"


require "./r1cs/r1cs.cr"
require "./r1cs/gate.cr"
require "benchmark"


module Isekai



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


class ZKPBenchmark
    @root : String = ""
    def zksnark_benchmark (opts : ProgramOptions)
        j1cs_name = @root + ".j128";

        report = r1cs_benchmark(j1cs_name, opts);
    
        snarc = LibSnark.new();
        report += "\n#{opts.zkp_scheme}- Generate Trusted setup:"; 
        bench = Benchmark.measure {  snarc.vcSetup(j1cs_name, @root + ".s", opts.zkp_scheme.value.to_u8) }
        report +=  bench.to_s
        report +=  "\n#{opts.zkp_scheme} - Generate proof:"; 
        bench = Benchmark.measure{  snarc.proof(@root + ".s", j1cs_name + ".in", @root + ".p", opts.zkp_scheme.value.to_u8) }
        report +=  bench.to_s
        report +=  "\n#{opts.zkp_scheme} - Verify proof:"; 
        bench = Benchmark.measure {  snarc.verify(@root + ".s", j1cs_name + ".in", @root + ".p") }
        report +=  bench.to_s
        return report;
    end

    def bulletproof_benchmark(opts : ProgramOptions)
        j1cs_bp = @root + ".j1bp";
        report = r1cs_benchmark(j1cs_bp, opts);
        ##bulletproof
        report +=  "\nBulletproof - Generate proof:"; 
        bench = Benchmark.measure {   LibProof.bpProve(j1cs_bp, @root + ".p") }
        report +=  bench.to_s
        report +=  "\nBulletproof - Verify proof:"; 
        bench = Benchmark.measure {  LibProof.bpVerify(j1cs_bp, @root + ".p") }
        report +=  bench.to_s
        return report;
    end

    def r1cs_benchmark(j1cs_name, opts : ProgramOptions)
        arith_name = @root + ".ari";
        report = "";
        if !(File.exists?(j1cs_name))
            ##generate r1cs for bulletproof
            gates = GateKeeper.new(arith_name, arith_name+".in" , j1cs_name, Hash(UInt32,InternalVar).new, opts.zkp_scheme)
            report += "\nCreate r1cs for #{opts.zkp_scheme}:" ;
            bench = Benchmark.measure {  gates.process_circuit };
            report +=  bench.to_s   
        end
        return report
    end

    def iop_benchmark (opts : ProgramOptions) 
        j1cs_name = @root + ".j128";
        report = r1cs_benchmark(j1cs_name, opts);
        snarc = LibSnark.new()
       
        snarc = LibSnark.new();
        report += "\n#{opts.zkp_scheme}- Proof&Verify (..todo):"; 
        bench = Benchmark.measure {  snarc.proof(@root + ".s", j1cs_name, @root + ".p", opts.zkp_scheme.value.to_u8) }
        report +=  bench.to_s
  
        return report;
    end

    # Main
    def benchmark(filename : String, bench)
        @root = filename
        case filename
            when .ends_with? ".c"
                @root = filename[0, filename.size() -2]
            when .ends_with? ".bc"
                @root = filename[0, filename.size() -3]
            else
        end
        opts = ProgramOptions.new
        schemes = [] of ZKP;
        bench.split(',', remove_empty: true)      {       |str|           
         if (scheme = ZKP.parse?(str))
                schemes <<  scheme
            end
        }
        if schemes.size() == 0
            schemes = [ ZKP::Bctv14a , ZKP::Groth16, ZKP::Dalek, ZKP::Ligero ];
        end
    
        arith_name = @root + ".ari";
        report : String = ""
        ##generate circuit
        if !(File.exists?(arith_name))
            input_file = InputFile.new(filename)
            report =  "Create circuit:"; 
            bench = Benchmark.measure { ParserProgram.new.create_circuit(input_file, arith_name, "" , opts) };
            report +=  bench.to_s
        end

        schemes.each do |scheme|
            opts.zkp_scheme = scheme
            puts "Benchmarking #{scheme}..."
            case scheme
            when .dalek?
                report  += bulletproof_benchmark(opts);
            when .groth16? , .bctv14a?
                report += zksnark_benchmark(opts);
            when .aurora?, .ligero?
                report += iop_benchmark(opts);
            when .snark?
                ##TODO add groth16 and bctv14a in the list; better to do this whne creating the array
            when .libsnark?, .libsnark_legacy?
                ##TODO: we should create the r1cs with the scheme, then it is up to the user to put this scheme *before* the other snarks, and if there is none, we should alos add groth16  (or both?)
            end
        end
    
        puts report;
    end
end

end