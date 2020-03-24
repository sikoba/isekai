require "../common/dfg"
require "../common/bitwidth"
require "./assumption"
require "./structure"
require "./type_utils"
require "llvm-crystal/lib_llvm"

module Isekai::LLVMFrontend

# Assumes that both 'a' and 'b' are of integer type.
def self.sign_extend_to_common_bitwidth (a : DFGExpr, b : DFGExpr) : {DFGExpr, DFGExpr}
    case a.@bitwidth <=> b.@bitwidth
    when .< 0
        a = SignExtend.bake(a, b.@bitwidth)
    when .> 0
        b = SignExtend.bake(b, a.@bitwidth)
    end
    {a, b}
end

# Assumes that both 'a' and 'b' are of integer type.
def self.bitwidth_safe_signed_add (a : DFGExpr, b : DFGExpr) : DFGExpr
    x, y = self.sign_extend_to_common_bitwidth(a, b)
    Add.bake(x, y)
end

def self.make_undef_array_elem (arr : Structure) : DFGExpr
    type = arr.@type
    raise "unreachable" unless type.array?
    return TypeUtils.make_undef_expr_of_type(type.element_type)
end

abstract class AbstractPointer < DFGExpr
    def initialize ()
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
    def initialize (@target_type : LibLLVM::Type)
        super()
    end

    def load (assumption : Assumption) : DFGExpr
        Log.log.info("possible undefined behavior: load from uninitialized pointer")
        TypeUtils.make_undef_expr_of_type(@target_type)
    end

    def store! (value : DFGExpr, assumption : Assumption) : Nil
        Log.log.info("possible undefined behavior: store at uninitialized pointer")
    end

    def move (by offset : DFGExpr) : DFGExpr
        self
    end
end

class PastOnePointer < AbstractPointer
    def initialize (@original : AbstractPointer)
        super()
    end

    def load (assumption : Assumption) : DFGExpr
        Log.log.info("possible undefined behavior: load from past-one pointer")
        @original.load(assumption)
    end

    def store! (value : DFGExpr, assumption : Assumption) : Nil
        Log.log.info("possible undefined behavior: store at past-one pointer")
    end

    def move (by offset : DFGExpr) : DFGExpr
        Conditional.bake(
            # 'offset' is zero?
            CmpEQ.bake(
                offset,
                Constant.new(0_i64, bitwidth: offset.@bitwidth)),
            # Then, the result is 'self'.
            self,
            # Otherwise, the result is '@original' because moving this pointer past any value other
            # than -1 is undefined behavior.
            @original)
    end
end

# Points to an exactly one instance of an object. Used for on-stack allocations and input/output
# structs.
class StaticPointer < AbstractPointer
    def initialize (@target : DFGExpr)
        super()
    end

    def load (assumption : Assumption) : DFGExpr
        assumption.reduce(@target)
    end

    def store! (value : DFGExpr, assumption : Assumption) : Nil
        @target = assumption.conditionalize(
            old_expr: @target,
            new_expr: value)
    end

    def move (by offset : DFGExpr) : DFGExpr
        Conditional.bake(
            # 'offset' is zero?
            CmpEQ.bake(
                offset,
                Constant.new(value: 0_i64, bitwidth: offset.@bitwidth)),
            # Then the result is 'self'.
            self,
            # Otherwise, the result is 'PastOnePointer.new(self)' because moving this pointer past
            # any value other than 1 is undefined behavior.
            PastOnePointer.new(self))
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

    def field_as_expr
        Constant.new(@field.to_i64, bitwidth: BitWidth.new(32))
    end

    def load (assumption : Assumption) : DFGExpr
        unless valid?
            Log.log.info("possible undefined behavior: array index is out of bounds")
            return LLVMFrontend.make_undef_array_elem(@base)
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
        if @base.@type.struct?
            Conditional.bake(
                # 'offset' is zero?
                CmpEQ.bake(
                    offset,
                    Constant.new(value: 0_i64, bitwidth: offset.@bitwidth)),
                # Then, the result is 'self'.
                self,
                # Otherwise, the result is 'PastOnePointer.new(self)' because moving this pointer
                # past any value other than 1 is undefined behavior.
                PastOnePointer.new(self))
        else
            new_field = LLVMFrontend.bitwidth_safe_signed_add(offset, field_as_expr)
            PointerFactory.bake_field_pointer(base: @base, field: new_field)
        end
    end
end

# Points to an array element with statically unknown index.
class DynamicFieldPointer_legacy < AbstractPointer
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

    def load (assumption : Assumption) : DFGExpr
        unless (n = @max_size)
            Log.log.info("possible undefined behavior: index is undefined or always invalid")
            return LLVMFrontend.make_undef_array_elem(@base)
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
        return PointerFactory.bake_field_pointer(base: @base, field: new_field)
    end
end


class DynamicFieldPointer < DynamicFieldPointer_legacy
    ##TODO to test
    def load (assumption : Assumption) : DFGExpr
        unless (n = @max_size)
            Log.log.info("possible undefined behavior: index is undefined or always invalid")
            return LLVMFrontend.make_undef_array_elem(@base)
        end
        storage = (0...n).map { |i| assumption.reduce(@base.@elems[i]) }
        DynLoad.new(storage: storage, idx: @field)
    end

    #load using asplit gate. It should replace the load function BUT the result is not as good as with the dedicated dload gate (r1cs is much bigger). However the dload gate does the same as this so we should have only the asplit gate.. TODO make it as optimised as dload.
    def load_split (assumption : Assumption) : DFGExpr
        unless (n = @max_size)
            Log.log.info("possible undefined behavior: index is undefined or always invalid")
            return LLVMFrontend.make_undef_array_elem(@base)
        end

        result = assumption.reduce(@base.@elems[0])
        zero = Constant.new(0_i64, bitwidth: result.@bitwidth)
        (1...n).each do |i|
            di = Asplit.new(@field, i, n)            
            result = Add.bake(
                result,
                Conditional.bake(
                    di,
                    assumption.reduce(@base.@elems[i]),
                    zero))
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
                di = Asplit.new(@field, i, n)
                assumption.push(di, true)
                @base.@elems[i] = assumption.conditionalize(
                    old_expr: @base.@elems[i],
                    new_expr: value)
                assumption.pop
            end
        end
    end
end


# The idea is that we can always "reduce" pointer comparison of a pair
#     {AbstractPointer, AbstractPointer}
# to another pair of
#     {DFGExpr, DFGExpr}
# representing *integer* values (of equal bitwidth) that compare the same. This possibly includes
# making up a pair of constants if we know at compile-time how those pointers should compare.
# The caller should do something like
#     x, y = PointerComparator.compare_pointers(p, q)
#     result = <CmpClass>.bake(x, y)
# so that the result of constant comparison is folded to a constant in '<CmpClass>.bake()'.
#
# Now, for pointer comparison rules. The C standard says pointers to different objects can be
# compared with "==" and "!=", and those comparison shall behave as if the pointers are not equal,
# but if you compare them with "<", "<=", ">" or ">=", a conforming implementation may return
# random/inconsistent junk as a result of these comparisons.
#
# We kind of take advantage of this wording and return a pair of constants representing
# "greater" whenever we see such a comparison. Such places in the code are marked with the word
# "unequal".

module PointerComparator
    private def self.from_numbers (a : Int64, b : Int64) : {DFGExpr, DFGExpr}
        bitwidth = BitWidth.new(8)
        {Constant.new(a, bitwidth), Constant.new(b, bitwidth)}
    end

    private def self.equal()
        return self.from_numbers(0, 0)
    end

    private def self.greater()
        return self.from_numbers(1, 0)
    end

    private def self.compare_past_one_pointer (a : PastOnePointer, b : AbstractPointer) : {DFGExpr, DFGExpr}
        if b.is_a? PastOnePointer
            # We are asked to compare '(x + 1)' to '(y + 1)', so let's compare 'x' to 'y'.
            self.reduce_pointer_comparison(a.@original, b.@original)
        else
            # Everything else is ether less than or "unequal" to a.
            self.greater()
        end
    end

    private def self.field_pointer_index (
            a : StaticFieldPointer | DynamicFieldPointer_legacy) : DFGExpr

        if a.is_a? StaticFieldPointer
            a.field_as_expr
        else
            a.@field
        end
    end

    private def self.compare_field_pointers (
            a : StaticFieldPointer | DynamicFieldPointer_legacy,
            b : StaticFieldPointer | DynamicFieldPointer_legacy) : {DFGExpr, DFGExpr}

        if a.@base.same?(b.@base)
            LLVMFrontend.sign_extend_to_common_bitwidth(
                self.field_pointer_index(a),
                self.field_pointer_index(b))
        else
            # "unequal"
            self.greater()
        end
    end

    def self.reduce_pointer_comparison (a : AbstractPointer, b : AbstractPointer) : {DFGExpr, DFGExpr}
        case a

        when UndefPointer
            # This is actually undefined behavior, but let's say they are "unequal".
            self.greater()

        when PastOnePointer
            self.compare_past_one_pointer(a, b)

        when StaticPointer
            case b
            when StaticPointer
                if b.@target.same?(a.@target)
                    self.equal()
                else
                    # "unequal"
                    self.greater()
                end
            when PastOnePointer
                left, right = self.compare_past_one_pointer(b, a)
                {right, left}
            else
                # "unequal"
                self.greater()
            end

        when StaticFieldPointer
            case b
            when StaticFieldPointer
                self.compare_field_pointers(a, b)
            when DynamicFieldPointer_legacy
                self.compare_field_pointers(a, b)
            when PastOnePointer
                left, right = self.compare_past_one_pointer(b, a)
                {right, left}
            else
                # "unequal"
                self.greater()
            end

        when DynamicFieldPointer_legacy
            case b
            when StaticFieldPointer
                self.compare_field_pointers(a, b)
            when DynamicFieldPointer_legacy
                self.compare_field_pointers(a, b)
            when PastOnePointer
                left, right = self.compare_past_one_pointer(b, a)
                {right, left}
            else
                # "unequal"
                self.greater()
            end

        else
            raise "unreachable"
        end
    end
end # module Isekai::LLVMFrontend::PointerComparator


module PointerFactory
    def self.bake_field_pointer (base : Structure, field : DFGExpr) : AbstractPointer
        if field.is_a? Constant
            return StaticFieldPointer.new(base: base, field: field.@value.to_i32!)
        else
            # If this is an array of non-integers, we should use 'DynamicFieldPointer_legacy',
            # otherwise 'DynamicFieldPointer' (if the array is empty, there is no difference.)
            if (e = base.@elems.first?) && e.@bitwidth.undefined?
                return DynamicFieldPointer_legacy.new(base: base, field: field)
            else
                return DynamicFieldPointer.new(base: base, field: field)
            end
        end
    end
end # module Isekai::LLVMFrontend::PointerFactory

end # module Isekai::LLVMFrontend
