require "llvm-crystal/lib_llvm"

module Isekai::LLVMFrontend

private class ControlFlowGraph
    @blocks = [] of LibLLVM::BasicBlock
    @block2idx = {} of LibLLVM::BasicBlock => Int32
    @final_idx : Int32 = -1

    private def discover (bb : LibLLVM::BasicBlock)
        return if @block2idx.has_key? bb

        idx = @blocks.size
        @blocks << bb
        @block2idx[bb] = idx

        has_succ = false
        bb.terminator.successors.each do |succ|
            has_succ = true
            discover(succ)
        end
        unless has_succ
            raise "Multiple final blocks" unless @final_idx == -1
            @final_idx = idx
        end
    end

    def initialize (entry : LibLLVM::BasicBlock)
        discover(entry)
        raise "No final block" if @final_idx == -1
    end

    def nvertices
        return @blocks.size
    end

    def final_block_idx
        return @final_idx
    end

    def edges_from (v : Int32)
        return @blocks[v].terminator.successors.map { |bb| @block2idx[bb] }
    end

    def block_to_idx (bb : LibLLVM::BasicBlock)
        return @block2idx[bb]
    end

    def idx_to_block (idx : Int32)
        return @blocks[idx]
    end
end

end
