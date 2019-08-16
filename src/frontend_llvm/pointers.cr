require "../common/dfg"
require "../common/bitwidth"
require "./structure"
require "./type_utils"
require "llvm-crystal/lib_llvm_c"

module Isekai::LLVMFrontend
extend self

# Assumes that both 'a' and 'b' are of integer type.
def bitwidth_safe_signed_add (a : DFGExpr, b : DFGExpr) : DFGExpr
    case a.@bitwidth <=> b.@bitwidth
    when .< 0
        a = Isekai.dfg_make_bitwidth_cast(SignExtend, a, b.@bitwidth)
    when .> 0
        b = Isekai.dfg_make_bitwidth_cast(SignExtend, b, a.@bitwidth)
    end
    return Isekai.dfg_make_binary(Add, a, b)
end

def make_undef_array_elem (arr : Structure) : DFGExpr
    sig = TypeUtils.get_complex_type_signature(arr.@ty)
    case sig
    when {LibLLVM_C::TypeRef, Int32}
        # array
        elem_ty, nelems = sig
        return TypeUtils.make_undef_expr_of_ty(elem_ty)
    else
        # structure or something
        raise "unreachable"
    end
end

abstract class AbstractPointer < DFGExpr
    def initialize ()
        super(bitwidth: BitWidth.new_for_undefined)
    end

    # Should return '*ptr'
    abstract def load : DFGExpr

    # Should perform '*ptr = value'
    abstract def store! (value : DFGExpr)

    # Should return 'ptr + offset'
    abstract def move (by offset : DFGExpr) : DFGExpr
end

class UndefPointer < AbstractPointer
    def initialize (@target_ty : LibLLVM_C::TypeRef)
        super()
    end

    def load : DFGExpr
        Log.log.info("possible undefined behavior: load from uninitialized pointer")
        return TypeUtils.make_undef_expr_of_ty(@target_ty)
    end

    def store! (value : DFGExpr)
        Log.log.info("possible undefined behavior: store at uninitialized pointer")
    end

    def move (by offset : DFGExpr) : AbstractPointer
        return self
    end
end

# Points to an exactly one instance of an object. Used for on-stack allocations and input/output
# structs.
class StaticPointer < AbstractPointer
    def initialize (@target : DFGExpr)
        super()
    end

    def load : DFGExpr
        @target
    end

    def store! (value : DFGExpr)
        @target = value
    end

    def move (by offset : DFGExpr) : DFGExpr
        # Technically, we can move this pointer past *one* element, but cannot dereference the
        # resulting pointer. Since we can't compare pointers, this implementation is OK.
        return self
    end
end

# Points to a field of a structure or an array element with statically known index.
class StaticFieldPointer < AbstractPointer
    def initialize (@base : Structure, @field : Int32)
        super()
    end

    def valid?
        0 <= @field < @base.@elems.size
    end

    def load : DFGExpr
        unless valid?
            Log.log.info("possible undefined behavior: array index is out of bounds")
            return LLVMFrontend.make_undef_array_elem(@base)
        end
        @base.@elems[@field]
    end

    def store! (value : DFGExpr)
        unless valid?
            Log.log.info("possible undefined behavior: array index is out of bounds")
            return
        end
        @base.@elems[@field] = value
    end

    def move (by offset : DFGExpr) : DFGExpr
        new_field = LLVMFrontend.bitwidth_safe_signed_add(
            offset,
            Constant.new(@field.to_i64, BitWidth.new(32)))
        return PointerFactory.bake_field_pointer(base: @base, field: new_field)
    end
end

# Points to an array element with statically unknown index.
class DynamicFieldPointer < AbstractPointer
    @max_size : Int32?

    # Assumes that '@field' is of integer type.
    def initialize (@base : Structure, @field : DFGExpr)
        super()

        unless @base.@elems.empty?
            bitwidth = @field.@bitwidth
            # Like 'min(@base.@elems.@size, bitwidth.mask + 1)' but without overflow issues.
            @max_size = ((@base.@elems.size - 1) & bitwidth.mask) + 1
        else
            # This is OK as long as the pointer is never dereferenced.
            @max_size = nil
        end
    end

    private def make_bsearch_expr (left, right)
        n = right - left
        case n
        when 1
            return @base.@elems[left]

        # A micro-optimization: 'CmpEQ' is lighter resourse-wise.
        when 2, 3
            left_const = Constant.new(left.to_i64, bitwidth: @field.@bitwidth)
            return Isekai.dfg_make_conditional(
                Isekai.dfg_make_binary(CmpEQ, @field, left_const),
                @base.@elems[left],
                make_bsearch_expr(left + 1, right))

        else
            pivot = left + n // 2
            pivot_const = Constant.new(pivot.to_i64, bitwidth: @field.@bitwidth)
            return Isekai.dfg_make_conditional(
                Isekai.dfg_make_binary(CmpLT, @field, pivot_const),
                make_bsearch_expr(left, pivot),
                make_bsearch_expr(pivot, right))
        end
    end

    def load : DFGExpr
        unless (n = @max_size)
            Log.log.info("possible undefined behavior: index is undefined or always invalid")
            return LLVMFrontend.make_undef_array_elem(@base)
        end
        return make_bsearch_expr(0, n)
    end

    def store! (value : DFGExpr)
        unless (n = @max_size)
            Log.log.info("possible undefined behavior: index is undefined or always invalid")
            return
        end

        if n == 1
            @base.@elems[0] = value
        else
            (0...n).each do |i|
                i_const = Constant.new(i.to_i64, bitwidth: @field.@bitwidth)
                @base.@elems[i] = Isekai.dfg_make_conditional(
                    Isekai.dfg_make_binary(CmpEQ, @field, i_const),
                    value,
                    @base.@elems[i])
            end
        end
    end

    def move (by offset : DFGExpr) : DFGExpr
        new_field = LLVMFrontend.bitwidth_safe_signed_add(offset, @field)
        return PointerFactory.bake_field_pointer(base: @base, field: new_field)
    end
end

module PointerFactory
    def self.bake_field_pointer (base : Structure, field : DFGExpr) : AbstractPointer
        if field.is_a? Constant
            return StaticFieldPointer.new(base: base, field: field.@value.to_i32)
        else
            return DynamicFieldPointer.new(base: base, field: field)
        end
    end
end # module PointerFactory

end # module Isekai::LLVMFrontend
