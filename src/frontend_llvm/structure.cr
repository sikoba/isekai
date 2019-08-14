require "../common/dfg"
require "../common/bitwidth"
require "llvm-crystal/lib_llvm_c"

module Isekai::LLVMFrontend

# This type represents both a structure and an array.
private class Structure < DFGExpr
    def initialize (@elems : Array(DFGExpr), @ty : LibLLVM_C::TypeRef)
        super(BitWidth.new(BitWidth::UNSPECIFIED))
    end

    def visit (&block : DFGExpr ->)
        @elems.each do |elem|
            if elem.is_a? Structure
                elem.visit &block
            else
                block.call elem
            end
        end
    end

    def flattened
        arr = [] of DFGExpr
        visit { |elem| arr << elem }
        arr
    end
end

end
