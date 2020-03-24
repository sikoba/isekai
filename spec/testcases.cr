require "spec"
require "../src/frontend_llvm/parser.cr"
require "../src/backend_alt/arith/board"
require "../src/backend_alt/arith/req_factory"
require "../src/backend_alt/arith/backend"
require "../src/backend_alt/lay_down_output"

# Please note this file only compiles and runs isekai on the test cases, and does not check the
# generated circuits.

def stringify_status (status : Process::Status) : String
    case status
    when .normal_exit?
        "exited with code #{status.exit_code}"
    when .signal_exit?
        "killed by signal #{status.exit_signal}"
    else
        "did something unexpected"
    end
end

def compile_program (filename : String, &block : String ->)
    File.tempfile(suffix: ".bc") do |result|
        status = Process.run(
            "clang",
            ["-O0", "-Wall", "-Wextra", "-c", "-emit-llvm", filename, "-o", result.path],
            output: Process::ORIGINAL_STDOUT,
            error: Process::ORIGINAL_STDERR)
        unless status.success?
            raise "clang failed: #{stringify_status status}"
        end
        yield result.path
    end
end

def run_isekai (on bitcode_file : String) : Nil
    File.open(File::NULL, "w") do |null_output|
        parser = Isekai::LLVMFrontend::Parser.new(
            bitcode_file,
            loop_sanity_limit: 1_000_000,
            p_bits_min: 254)
        inputs, nizk_inputs, outputs = parser.parse()
        board = Isekai::AltBackend::Arith::Board.new(
            inputs,
            nizk_inputs,
            output: null_output,
            p_bits_min: 254,
            p_bits_max: 254)
        req_factory = Isekai::AltBackend::Arith::RequestFactory.new(board)
        backend = Isekai::AltBackend::Arith::Backend.new(req_factory)
        outputs.each { |expr| Isekai::AltBackend.lay_down_output(backend, expr) }
        board.done!
    end
end

def test_all_matches (pattern : String) : Nil
    Dir.glob(pattern) do |match|
        it "compiles '#{match}'" do
            compile_program(match) do |bitcode|
                run_isekai(on: bitcode)
            end
        end
    end
end

describe "Back-end tests" do
    %w(c cpp cxx).each do |ext|
        test_all_matches "./tests/backend/testcases/*/prog.#{ext}"
    end
end

describe "Front-end tests" do
    test_all_matches "./tests/frontend/[^_]*.c"
end
