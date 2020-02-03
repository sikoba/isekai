
require "./spec_helper"
require "../src/zksnark/libsnark.cr"
require "file_utils.cr"
require "../src/r1cs/gate.cr"
#require "../src/r1cs/r1cs.cr"
#require "spec"


describe LibSnark do
    
    scheme = Isekai::ZKP::Groth16; 

    it "TrustedSetup" do    
        snarc = LibSnark.new()
        snarc.vcSetup("spec/simple_example.r1cs", "temp", scheme.to_u8)
        File.exists?("temp").should eq(true)
        FileUtils.rm("temp")
    end

    it "Proof and Verify" do
        snarc = LibSnark.new()
       # scheme = ZKP::Groth16; #TODO
        gates : Isekai::GateKeeper = Isekai::GateKeeper.new("spec/simple_example.arith", "spec/simple_example.in", "temp.r1", Hash(UInt32, Isekai::InternalVar).new, scheme)
        gates.process_circuit;
        File.exists?("temp.r1").should eq(true)
        snarc.vcSetup("temp.r1", "temp.s", scheme.to_u8)
        File.exists?("temp.s").should eq(true)
        snarc.proof("temp.s", "temp.r1.in", "temp.p", scheme.to_u8)
        File.exists?("temp.p").should eq(true)
        result = snarc.verify("temp.s", "temp.r1.in", "temp.p")
        result.should eq(true)
        
        FileUtils.rm("temp.r1")
        FileUtils.rm("temp.r1.in")
        FileUtils.rm("temp.s")
        FileUtils.rm("temp.p")
    end
    it "R1CS" do
        gates : Isekai::GateKeeper = Isekai::GateKeeper.new("spec/simple_example.arith", "spec/simple_example.in", "temp.r1", Hash(UInt32, Isekai::InternalVar).new, scheme)
        gates.process_circuit;
        File.exists?("temp.r1").should eq(true)   
        FileUtils.rm("temp.r1")

    end

end
