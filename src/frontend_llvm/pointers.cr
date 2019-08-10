require "../common/dfg"
require "../common/bitwidth"
require "./structure"

include Isekai

private def bitwidth_safe_signed_add (a : DFGExpr, b : DFGExpr) : DFGExpr
    raise "One of the summands is not an integer" unless
        a.@bitwidth.integer? && b.@bitwidth.integer?
    case a.@bitwidth <=> b.@bitwidth
    when .< 0
        a = Isekai.dfg_make_bitwidth_cast(SignExtend, a, b.@bitwidth)
    when .> 0
        b = Isekai.dfg_make_bitwidth_cast(SignExtend, b, a.@bitwidth)
    end
    return Isekai.dfg_make_binary(Add, a, b)
end

module Isekai::LLVMFrontend::Pointers

class UndefinedBehavior < Exception
end

class UndefPointer < AbstractPointer
    def initialize ()
        super()
    end

    def load : DFGExpr
        raise UndefinedBehavior.new
    end

    def store! (value : DFGExpr)
        raise UndefinedBehavior.new
    end

    def move (by offset : DFGExpr) : DFGExpr
        return self
    end
end

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

class StaticFieldPointer < AbstractPointer
    def initialize (@base : Structure, @field : Int32)
        super()
    end

    def can_deref?
        0 <= @field < @base.@elems.size
    end

    def load : DFGExpr
        raise UndefinedBehavior.new unless can_deref?
        @base.@elems[@field]
    end

    def store! (value : DFGExpr)
        raise UndefinedBehavior.new unless can_deref?
        @base.@elems[@field] = value
    end

    def move (by offset : DFGExpr) : DFGExpr
        new_field = bitwidth_safe_signed_add(
            offset,
            Constant.new(@field.to_i64, BitWidth.new(32)))
        return Pointers.bake_field_pointer(base: @base, field: new_field)
    end
end

class DynamicFieldPointer < AbstractPointer
    @max_size : Int32?

    def initialize (@base : Structure, @field : DFGExpr)
        super()

        bitwidth = @field.@bitwidth
        raise "Array index is not an integer" unless bitwidth.integer?

        unless @base.@elems.empty?
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
            pivot = left + n / 2
            pivot_const = Constant.new(pivot.to_i64, bitwidth: @field.@bitwidth)
            return Isekai.dfg_make_conditional(
                Isekai.dfg_make_binary(CmpLT, @field, pivot_const),
                make_bsearch_expr(left, pivot),
                make_bsearch_expr(pivot, right))
        end
    end

    def load : DFGExpr
        raise UndefinedBehavior.new unless (n = @max_size)
        return make_bsearch_expr(0, n)
    end

    def store! (value : DFGExpr)
        raise UndefinedBehavior.new unless (n = @max_size)
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
        new_field = bitwidth_safe_signed_add(offset, @field)
        return Pointers.bake_field_pointer(base: @base, field: new_field)
    end
end

def self.bake_field_pointer (base : Structure, field : DFGExpr) : AbstractPointer
    if field.is_a? Constant
        return StaticFieldPointer.new(base: base, field: field.@value.to_i32)
    else
        return DynamicFieldPointer.new(base: base, field: field)
    end
end

end
