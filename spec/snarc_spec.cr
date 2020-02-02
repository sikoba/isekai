
require "./spec_helper"
require "../src/zksnark/libsnark"
require "file_utils.cr"



describe LibSnark do
    scheme = 1_u8; #TODO
    it "TrustedSetup" do
        snarc = LibSnark.new()
        snarc.vcSetup("spec/simple_example.r1cs", "temp", scheme)
        File.exists?("temp").should eq(true)
        FileUtils.rm("temp")
    end

    it "Proof and Verify" do
        snarc = LibSnark.new()
        snarc.generateR1cs("spec/simple_example.arith","spec/simple_example.in", "temp.r1")
        File.exists?("temp.r1").should eq(true)
        snarc.vcSetup("temp.r1", "temp.s", scheme)
        File.exists?("temp.s").should eq(true)
        snarc.proof("temp.s", "temp.r1.in", "temp.p", scheme)
        File.exists?("temp.p").should eq(true)
        result = snarc.verify("temp.s", "temp.r1.in", "temp.p")
        result.should eq(true)
        
        FileUtils.rm("temp.r1")
        FileUtils.rm("temp.r1.in")
        FileUtils.rm("temp.s")
        FileUtils.rm("temp.p")
    end

    it "R1CS" do
        snarc = LibSnark.new()
        snarc.generateR1cs("spec/simple_example.arith","spec/simple_example.in", "temp.r1")
        File.exists?("temp.r1").should eq(true)
        
        FileUtils.rm("temp.r1")

    end

end
