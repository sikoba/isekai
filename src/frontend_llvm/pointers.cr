require "../common/dfg"
require "../common/bitwidth"
require "./assumption"
require "./structure"
require "./type_utils"
require "llvm-crystal/lib_llvm"

module Isekai::LLVMFrontend

# Assumes that both 'a' and 'b' are of integer type.
def self.bitwidth_safe_signed_add (a : DFGExpr, b : DFGExpr) : DFGExpr
    case a.@bitwidth <=> b.@bitwidth
    when .< 0
        a = SignExtend.bake(a, b.@bitwidth)
    when .> 0
        b = SignExtend.bake(b, a.@bitwidth)
    end
    return Add.bake(a, b)
end

def self.get_element_type (base : Structure, field : Int32?) : LibLLVM::Type
    type = base.@type
    case type.kind
    when .struct_type_kind?
        type.struct_elems[field.not_nil!]
    when .array_type_kind?
        type.element_type
    else
        raise "unreachable"
    end
end

abstract class AbstractPointer < DFGExpr
    def initialize (@target_type : LibLLVM::Type)
        super(bitwidth: BitWidth.new_for_undefined)
    end

    # Should return '*ptr' under the given assumption
    abstract def load (assumption : Assumption) : DFGExpr

    # Should perform '*ptr = value' under the given assumption
    abstract def store! (value : DFGExpr, assumption : Assumption) : Nil

    # Should return 'ptr + offset'
    abstract def move (by offset : DFGExpr) : DFGExpr
end

class UndefPointer < AbstractPointer
    def initialize (target_type : LibLLVM::Type)
        super(target_type)
    end

    def load (assumption : Assumption) : DFGExpr
        Log.log.info("possible undefined behavior: load from uninitialized pointer")
        return TypeUtils.make_undef_expr_of_type(@target_type)
    end

    def store! (value : DFGExpr, assumption : Assumption) : Nil
        Log.log.info("possible undefined behavior: store at uninitialized pointer")
    end

    def move (by offset : DFGExpr) : AbstractPointer
        return self
    end
end

# Points to an exactly one instance of an object. Used for on-stack allocations and input/output
# structs.
class StaticPointer < AbstractPointer
    def initialize (@target : DFGExpr, target_type : LibLLVM::Type)
        super(target_type)
    end

    def load (assumption : Assumption) : DFGExpr
        assumption.reduce(@target)
    end

    def store! (value : DFGExpr, assumption : Assumption) : Nil
        @target = assumption.conditionalize(old_expr: @target, new_expr: value)
    end

    def move (by offset : DFGExpr) : DFGExpr
        # Technically, we can move this pointer past *one* element, but cannot dereference the
        # resulting pointer. Since we can't compare pointers, this implementation is OK.
        return self
    end
end

# Points to a field of a structure or an array element with statically known index.
class StaticFieldPointer < AbstractPointer
    def initialize (@base : Structure, @field : Int32, target_type : LibLLVM::Type?)
        super(target_type || LLVMFrontend.get_element_type(base, field))
    end

    def valid?
        0 <= @field < @base.@elems.size
    end

    def load (assumption : Assumption) : DFGExpr
        unless valid?
            Log.log.info("possible undefined behavior: array index is out of bounds")
            return TypeUtils.make_undef_expr_of_type(@target_type)
        end
        assumption.reduce(@base.@elems[@field])
    end

    def store! (value : DFGExpr, assumption : Assumption) : Nil
        unless valid?
            Log.log.info("possible undefined behavior: array index is out of bounds")
            return
        end
        @base.@elems[@field] = assumption.conditionalize(
            old_expr: @base.@elems[@field],
            new_expr: value)
    end

    def move (by offset : DFGExpr) : DFGExpr
        new_field = LLVMFrontend.bitwidth_safe_signed_add(
            offset,
            Constant.new(@field.to_i64, bitwidth: BitWidth.new(32)))
        return PointerFactory.bake_field_pointer(
            base: @base,
            field: new_field,
            target_type: @target_type)
    end
end

# Points to an array element with statically unknown index.
class DynamicFieldPointer < AbstractPointer
    @max_size : Int32?

    # Assumes that '@field' is of integer type.
    def initialize (@base : Structure, @field : DFGExpr, target_type : LibLLVM::Type?)
        super(target_type || LLVMFrontend.get_element_type(base, field: nil))

        unless @base.@elems.empty?
            bitwidth = @field.@bitwidth
            # Like 'min(@base.@elems.@size, bitwidth.mask + 1)' but without overflow issues.
            @max_size = ((@base.@elems.size - 1) & bitwidth.mask) + 1
        else
            # This is OK as long as the pointer is never dereferenced.
            @max_size = nil
        end
    end

    def load (assumption : Assumption) : DFGExpr
        unless (n = @max_size)
            Log.log.info("possible undefined behavior: index is undefined or always invalid")
            return TypeUtils.make_undef_expr_of_type(@target_type)
        end
        result = assumption.reduce(@base.@elems[0])
        (1...n).each do |i|
            i_const = Constant.new(i.to_i64, bitwidth: @field.@bitwidth)
            result = Conditional.bake(
                CmpEQ.bake(@field, i_const),
                assumption.reduce(@base.@elems[i]),
                result)
        end
        return result
    end

    def store! (value : DFGExpr, assumption : Assumption) : Nil
        unless (n = @max_size)
            Log.log.info("possible undefined behavior: index is undefined or always invalid")
            return
        end

        if n == 1
            @base.@elems[0] = assumption.conditionalize(
                old_expr: @base.@elems[0],
                new_expr: value)
        else
            (0...n).each do |i|
                i_const = Constant.new(i.to_i64, bitwidth: @field.@bitwidth)
                assumption.push(CmpEQ.bake(@field, i_const), true)
                @base.@elems[i] = assumption.conditionalize(
                    old_expr: @base.@elems[i],
                    new_expr: value)
                assumption.pop
            end
        end
    end

    def move (by offset : DFGExpr) : DFGExpr
        new_field = LLVMFrontend.bitwidth_safe_signed_add(offset, @field)
        return PointerFactory.bake_field_pointer(
            base: @base,
            field: new_field,
            target_type: @target_type)
    end
end

module PointerFactory
    def self.bake_field_pointer (
            base : Structure,
            field : DFGExpr,
            target_type : LibLLVM::Type?) : AbstractPointer

        if field.is_a? Constant
            return StaticFieldPointer.new(base, field.@value.to_i32, target_type)
        else
            return DynamicFieldPointer.new(base, field, target_type)
        end
    end
end # module Isekai::LLVMFrontend::PointerFactory

end # module Isekai::LLVMFrontend
