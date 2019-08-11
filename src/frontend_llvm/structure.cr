require "../common/dfg"
require "../common/bitwidth"
require "llvm-crystal/lib_llvm_c"

module Isekai::LLVMFrontend

private class Structure < DFGExpr
    # @elem_ty is defined as follows:
    #   * 'T' for an array of type 'T[N]' (even if N == 0);
    #   * the void type for a struct type.
    def initialize (@elems : Array(DFGExpr), @elem_ty : LibLLVM_C::TypeRef)
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

    def modify (&block : DFGExpr -> DFGExpr)
        (0...@elems.size).each do |i|
            elem = @elems[i]
            if elem.is_a? Structure
                elem.modify &block
            else
                @elems[i] = block.call elem
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
