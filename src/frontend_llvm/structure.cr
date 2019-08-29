require "../common/dfg"
require "../common/bitwidth"
require "llvm-crystal/lib_llvm"

module Isekai::LLVMFrontend

# This type represents both a structure and an array.
class Structure < DFGExpr
    def initialize (@elems : Array(DFGExpr), @type : LibLLVM::Type)
        super(BitWidth.new_for_undefined)
    end

    def visit (&block : DFGExpr ->)
        @elems.each do |elem|
            if elem.is_a? Structure
                elem.visit &block
            else
                block.call elem
            end
        end
        self
    end

    def flattened
        arr = [] of DFGExpr
        visit { |elem| arr << elem }
        arr
    end
end

end
