require "./types"
require "./storage"
require "./symbol_table_key"
require "./dfgoperator"
require "./bitwidth"
require "./common"

private macro def_simplify_left (**kwargs)
    def self.simplify_left (const, right)
        {% for key, value in kwargs %}
            {% if key == :identity %}
                if const.@value == {{ value }}
                    return right
                end
            {% elsif key == :const %}
                if const.@value == {{ value[:match] }}
                    return Constant.new {{ value[:result] }}, bitwidth: right.@bitwidth
                end
            {% else %}
                {% raise "Invalid keyword argument" %}
            {% end %}
        {% end %}
        return self.new(const, right)
    end
end

private macro def_simplify_right (**kwargs)
    def self.simplify_right (left, const)
        {% for key, value in kwargs %}
            {% if key == :identity %}
                if const.@value == {{ value }}
                    return left
                end
            {% elsif key == :const %}
                if const.@value == {{ value[:match] }}
                    return Constant.new {{ value[:result] }}, bitwidth: left.@bitwidth
                end
            {% else %}
                {% raise "Invalid keyword argument" %}
            {% end %}
        {% end %}
        return self.new(left, const)
    end
end

module Isekai

# Internal expression node. All internal state expressions
# are instances of this class
abstract class DFGExpr
    #add_object_helpers

    def initialize (@bitwidth : BitWidth)
    end

    def collapse_dependencies ()
        raise "Undefined dependencies collapsing on #{self.class}"
    end

    def collapse_constants(collapser)
        raise "Undefined dependencies constants on #{self.class}"
    end

    def evaluate(collapser)
        raise "Undefined method evaluate on #{self.class}"
    end
end

# The void type - result of an expression that yields no value
# (it only performs side effects).
class Void < DFGExpr
    def initialize ()
        super(bitwidth: BitWidth.new_for_undefined)
    end

    #add_object_helpers
end

# Undefined operation. Raised if the operation is not supported.
class Undefined < DFGExpr
    def initialize ()
        super(bitwidth: BitWidth.new_for_undefined)
    end

    #add_object_helpers
    def evaluate (collapser)
        raise "Can't evaluate undefined expression."
    end

    def collapse_dependencies () : Array(DFGExpr)
        return Array(DFGExpr).new()
    end

    def collapse_constants(collapser) : DFGExpr
        return self
    end
end

class InputBase < DFGExpr
    enum Kind
        Input
        NizkInput
    end

    def initialize (@which : Kind, @idx : Int32, bitwidth)
        super(bitwidth)
    end
end

class Field < DFGExpr
    def initialize (@key : StorageKey, bitwidth)
        super(bitwidth)
    end

    def evaluate (collapser)
        return collapser.get_input(@key)
    end

    def collapse_dependencies () : Array(DFGExpr)
        return Array(DFGExpr).new()
    end

    def collapse_constants(collapser) : DFGExpr
        return self
    end

    def_equals @key
    def_hash @key
end

# Operation on the array.
class ArrayOp < DFGExpr
    def initialize ()
        super(bitwidth: BitWidth.new_for_undefined)
    end
end

# Reference to the part of an existing node
class StorageRef < ArrayOp
    #add_object_helpers
    # Constructs a reference to a storage.
    #
    # Params:
    #     type = type of the storage
    #     storage = storage instance
    #     idx = index in the storage
    def initialize (@type : Type, @storage : Storage, @idx : Int32)
        super()
    end

    # Returns:
    #     true if the StorageRef instance refers to a pointer
    def is_ptr?
        @type.is_a? PtrType 
    end

    # Returns:
    #    StorageKey instance pointing to the offset in th estorage
    def offset_key (offset)
        raise "Getting the offset out of the non-pointer" unless !is_ptr?
        return StorageKey.new(@storage, @idx + offset)
    end

    # Returns:
    #     symbol-table key analog to this storage ref
    def key
        if is_ptr?
            raise "Trying to eagerly lookup ptr"
        end

        return StorageKey.new(@storage, @idx)
    end

    # Creates reference to this storage
    # Returns:
    #     a StorageRef instance referring to this storage reference
    def ref
        raise "Can't get reference to a pointer" unless !is_ptr?
        return StorageRef.new(PtrType.new(@type), @storage, @idx)
    end

    # Resolves a reference to the storage
    # Returns:
    #     a StorageRef instance which is a result of dereferencing
    #     this StorageRef (inverse of ref operation)
    def deref
        ptr_type = @type.as PtrType
        return StorageRef.new(ptr_type.@base_type, @storage, @idx)
    end
end

# Integer constant node
class Constant < DFGExpr
    #add_object_helpers

    def initialize (@value : Int64, bitwidth)
        super(bitwidth)
    end

    def evaluate (collapser)
        return @value
    end

    def collapse_dependencies () : Array(DFGExpr)
        return Array(DFGExpr).new()
    end

    def collapse_constants(collapser) : DFGExpr
        return self
    end

    def_equals @value
    def_hash @value
end

# Conditional node. Consists itself of the condition, then and else branches.
class Conditional < DFGExpr
    #add_object_helpers
    def initialize (@cond : DFGExpr, @valtrue : DFGExpr, @valfalse : DFGExpr)
        super(valtrue.@bitwidth.common! valfalse.@bitwidth)
    end

    def set_operands! (cond, valtrue, valfalse)
        @cond = cond
        @valtrue = valtrue
        @valfalse = valfalse
    end

    def self.bake (cond : DFGExpr, valtrue : DFGExpr, valfalse : DFGExpr) : DFGExpr
        if cond.is_a? Constant
            return (cond.@value != 0) ? valtrue : valfalse
        else
            return self.new(cond, valtrue, valfalse)
        end
    end

    def evaluate (collapser)
        cond = collapser.lookup(@cond)

        if cond
            return collapser.lookup(@valtrue)
        else
            return collapser.lookup(@valfalse)
        end
    end

    def collapse_dependencies
        return [@cond, @valtrue, @valfalse]
    end

    def collapse_constants (collapser)
        begin
            return Constant.new(
                collapser.evaluate_as_constant(self).@value,
                bitwidth: @bitwidth)
        rescue
            return Conditional.new(
                collapser.lookup(@cond),
                collapser.lookup(@valtrue),
                collapser.lookup(@valfalse))
        end
    end

    def_equals @cond, @valtrue, @valfalse
end


# Binary operation. Perform `@op` on two operands `@left` and `@right`
abstract class BinaryOp < DFGExpr
    #add_object_helpers
    def initialize (@op : ::Symbol, @left : DFGExpr, @right : DFGExpr, bitwidth)
        super(bitwidth)
    end

    def self.bake (left : DFGExpr, right : DFGExpr) : DFGExpr
        case {left, right}
        when {Constant, Constant}
            bitwidth = left.@bitwidth.common! right.@bitwidth
            Constant.new(self.static_eval(left.@value, right.@value, bitwidth), bitwidth)
        when {Constant, _}
            self.simplify_left(left, right)
        when {_, Constant}
            self.simplify_right(left, right)
        else
            self.new(left, right)
        end
    end

    def set_operands! (left, right)
        @left = left
        @right = right
    end

    def evaluate (collapser)
        raise "Can't evaluate binary op"
    end

    def collapse_dependencies () : Array(DFGExpr)
        return Array(DFGExpr).new().push(@left).push(@right)
    end

    def collapse_constants(collapser) : DFGExpr
        left = collapser.lookup(@left)
        right = collapser.lookup(@right)
        collapsed = dup()
        collapsed.set_operands!(left, right)
        # check if the result of this is a constant
        begin
            evaluated_constant = collapser.evaluate_as_constant(collapsed)
            collapsed = evaluated_constant.dup
        rescue ex : NonconstantExpression
            # can't evaluate further
        end

        return collapsed
    end

    def_equals @op, @left, @right
    def_hash @op, @left, @right
end

# Binary mathematial operation. Performs `@op` (also represented by `DFGOperator`)
# on `@left` and `@right`, with the optional identity element (e.g. 0 for addition, 1 for multiplication).
abstract class BinaryMath < BinaryOp
    ##add_object_helpers
    def initialize (@op, @crystalop : DFGOperator, @identity : (Int32|Nil), @left, @right)
        super(@op, @left, @right, bitwidth: left.@bitwidth.common! right.@bitwidth)
    end

    def evaluate (collapser)
        return @crystalop.evaluate(collapser.lookup(@left), collapser.lookup(@right))
    end

    def collapse_dependencies : Array(DFGExpr)
        Array(DFGExpr).new().push(@left).push(@right)
    end

    def collapse_constants (collapser)
        basic_collapsing = super(collapser)

        # check if we can collapse out this operation
        if basic_collapsing.is_a? BinaryMath
            if left = basic_collapsing.@left.as? Constant 
                if left.@value == @identity
                    basic_collapsing = basic_collapsing.@right
                end
            elsif right = basic_collapsing.@right.as? Constant 
                if right.@value == @identity
                    basic_collapsing = basic_collapsing.@left
                end
            end
        end

        return basic_collapsing
    end
end

class BinaryPredicate < BinaryOp
    def initialize (@op, @left, @right)
        super(@op, @left, @right, bitwidth: BitWidth.new(1))
    end
end

# Add operation
class Add < BinaryMath
    #add_object_helpers
    def initialize (@left, @right)
        super(:plus, OperatorAdd.new, 0, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        return bitwidth.truncate(left.to_u64! &+ right.to_u64!).to_i64!
    end

    def_simplify_left identity: 0
    def_simplify_right identity: 0
end

# Multiply operation
class Multiply < BinaryMath
    #add_object_helpers
    def initialize (@left, @right)
        super(:multiply, OperatorMul.new, 1, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        return bitwidth.truncate(left.to_u64! &* right.to_u64!).to_i64!
    end

    def_simplify_left identity: 1, const: {match: 0, result: 0}
    def_simplify_right identity: 1, const: {match: 0, result: 0}
end

# Subtract operation
class Subtract < BinaryMath
    def initialize (@left, @right)
        super(:minus, OperatorSub.new, nil, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        return bitwidth.truncate(left.to_u64! &- right.to_u64!).to_i64!
    end

    def_simplify_left
    def_simplify_right identity: 0
end

# Divide operation
class Divide < BinaryMath
    def initialize (@left, @right)
        super(:divide, OperatorDiv.new, nil, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        if right == 0
            # Well, we have to compile something...
            Log.log.info("possible undefined behavior: division by zero")
            return 0_i64
        end
        # unsigned division; cannot overflow, so no truncate
        return (left.to_u64! // right.to_u64!).to_i64!
    end

    # 0 / x = 0
    def_simplify_left const: {match: 0, result: 0}
    # x / 1 = x
    def_simplify_right identity: 1
end

# Modulo operation
class Modulo < BinaryMath
    def initialize (@left, @right)
        super(:modulo, OperatorMod.new, nil, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        if right == 0
            # Well, we have to compile something...
            Log.log.info("possible undefined behavior: division by zero")
            return 0_i64
        end
        # unsigned modulo; cannot overflow, so no truncate
        return (left.to_u64! % right.to_u64!).to_i64!
    end

    # 0 % x = 0
    def_simplify_left const: {match: 0, result: 0}
    # x % 1 = 0
    def_simplify_right const: {match: 1, result: 0}
end

# Exclusive OR operation
class Xor < BinaryMath
    def initialize (@left, @right)
        super(:bitxor, OperatorXor.new, 0, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        # cannot overflow, so no truncate
        return left ^ right
    end

    def_simplify_left identity: 0
    def_simplify_right identity: 0
end

# Left shift operation
class LeftShift < BinaryMath
    def initialize (@left, @right)
        super(:lshift, LeftShiftOp.new, nil, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        shift = right.to_u64!
        return 0_i64 if shift >= 64
        return bitwidth.truncate(left.to_u64! << shift).to_i64!
    end

    # 0 << x = 0
    def_simplify_left const: {match: 0, result: 0}
    # x << 0 = x
    def_simplify_right identity: 0
end

# Unsigned (logical) right shift operation
class RightShift < BinaryMath
    def initialize (@left, @right)
        super(:urshift, RightShiftOp.new, nil, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        shift = right.to_u64!
        return 0_i64 if shift >= 64
        # cannot overflow, so no truncate
        return (left.to_u64! >> shift).to_i64!
    end

    # 0 >> x = 0
    def_simplify_left const: {match: 0, result: 0}
    # x >> 0 = x
    def_simplify_right identity: 0
end

# Signed (arithmetic) right shift operation
class SignedRightShift < BinaryMath
    def initialize (@left, @right)
        super(:srshift, RightShiftOp.new, nil, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        shift = right.to_i64!
        return 0_i64 unless 0 <= shift < 64
        signed_left = bitwidth.sign_extend_to(left.to_u64!, BitWidth.new(64))
        result = signed_left.to_i64! >> shift
        bitwidth.truncate(result.to_u64!).to_i64!
    end

    # 0 >> x = 0
    def_simplify_left const: {match: 0, result: 0}
    # x >> 0 = x
    def_simplify_right identity: 0
end

# bitwise-or operation
class BitOr < BinaryMath
    def initialize (@left, @right)
        super(:bitor, OperatorBor.new, 0, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        # cannot overflow, so no truncate
        return left | right
    end

    def_simplify_left identity: 0
    def_simplify_right identity: 0
end

# bitwise-and operation
class BitAnd < BinaryMath
    def initialize (@left, @right)
        super(:bitand, OperatorBAnd.new, nil, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        # cannot overflow, so no truncate
        return left & right
    end

    def_simplify_left const: {match: 0, result: 0}
    def_simplify_right const: {match: 0, result: 0}
end

# Logical And operation
class LogicalAnd < BinaryMath
    def initialize (@left, @right)
        super(:land, LogicalAndOp.new, nil, @left, @right)
    end
end

# Unsigned less-than compare operation
class CmpLT < BinaryPredicate
    def initialize (@left, @right)
        super(:u_lt, @left, @right)
    end

    def evaluate(collapser)
        begin
            return collapser.lookup(@left).as(Constant).@value < collapser.lookup(@right).as(Constant).@value
        rescue
            raise NonconstantExpression.new("can't evaluate #{@left} >= #{@right}")
        end
    end

    def self.static_eval (left, right, bitwidth)
        (left.to_u64! < right.to_u64!) ? 1_i64 : 0_i64
    end

    def_simplify_left
    def_simplify_right
end

# Signed less-than compare operation
class SignedCmpLT < BinaryPredicate
    def initialize (@left, @right)
        super(:s_lt, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        signed_left = bitwidth.sign_extend_to(left.to_u64!, BitWidth.new(64))
        signed_right = bitwidth.sign_extend_to(right.to_u64!, BitWidth.new(64))
        return signed_left.to_i64! < signed_right.to_i64! ? 1_i64 : 0_i64
    end

    def_simplify_left
    def_simplify_right
end

# Unsigned less-than-or-equal compare operation
class CmpLEQ < BinaryPredicate
    def initialize (@left, @right)
        super(:u_le, @left, @right)
    end

    def evaluate(collapser)
        begin
            return collapser.lookup(@left).as(Constant).@value <= collapser.lookup(@right).as(Constant).@value
        rescue
            raise NonconstantExpression.new("can't evaluate #{@left} <= #{@right}")
        end
    end

    def self.static_eval (left, right, bitwidth)
        (left.to_u64! <= right.to_u64!) ? 1_i64 : 0_i64
    end

    def_simplify_left
    def_simplify_right
end

# Signed less-than-or-equal compare operation
class SignedCmpLEQ < BinaryPredicate
    def initialize (@left, @right)
        super(:s_le, @left, @right)
    end

    def self.static_eval (left, right, bitwidth)
        signed_left = bitwidth.sign_extend_to(left.to_u64!, BitWidth.new(64))
        signed_right = bitwidth.sign_extend_to(right.to_u64!, BitWidth.new(64))
        return signed_left.to_i64! <= signed_right.to_i64! ? 1_i64 : 0_i64
    end

    def_simplify_left
    def_simplify_right
end

# Equal compare operation
class CmpEQ < BinaryPredicate
    def initialize (@left, @right)
        super(:eq, @left, @right)
    end

    def evaluate(collapser)
        begin
            return collapser.lookup(@left).as(Constant).@value == collapser.lookup(@right).as(Constant).@value
        rescue
            raise NonconstantExpression.new("can't evaluate #{@left} == #{@right}")
        end
    end

    def self.static_eval (left, right, bitwidth)
        (left == right) ? 1_i64 : 0_i64
    end

    def_simplify_left
    def_simplify_right
end

# Not-equal compare operation
class CmpNEQ < BinaryPredicate
    def initialize (@left, @right)
        super(:neq, @left, @right)
    end

    def evaluate(collapser)
        begin
            return collapser.lookup(@left).as(Constant).@value != collapser.lookup(@right).as(Constant).@value
        rescue
            raise NonconstantExpression.new("can't evaluate #{@left} != #{@right}")
        end
    end

    def self.static_eval (left, right, bitwidth)
        (left != right) ? 1_i64 : 0_i64
    end

    def_simplify_left
    def_simplify_right
end

# Greater-than compare operation
#class CmpGT < BinaryOp
#    def initialize (@left, @right)
#       super(">", @left, @right)
#    end
#
#    def evaluate(collapser)
#        begin
#            return collapser.lookup(@left).as(Constant).@value > collapser.lookup(@right).as(Constant).@value
#        rescue
#            raise NonconstantExpression.new("can't evaluate #{@left} > #{@right}")
#        end
#    end
#end

# Greater-than-or-equal compare operation
#class CmpGEQ < BinaryOp
#    def initialize (@left, @right)
#        super(">=", @left, @right)
#    end
#
#    def evaluate(collapser)
#        begin
#            return collapser.lookup(@left).as(Constant).@value >= collapser.lookup(@right).as(Constant).@value
#        rescue
#            raise NonconstantExpression.new("can't evaluate #{@left} >= #{@right}")
#        end
#    end
#end

# Unary operation. Perform `@op` on `@expr`
abstract class UnaryOp < DFGExpr
    #add_object_helpers

    @expr : DFGExpr

    def initialize (@op : ::Symbol, @expr : DFGExpr, bitwidth)
        super(bitwidth)
    end

    def initialize (@op : ::Symbol, @expr : DFGExpr)
        super(expr.@bitwidth)
    end

    def collapse_dependencies() : Array(DFGExpr)
        return [@expr]
    end

    def set_operand! (expr)
        @expr = expr
    end

    def collapse_constants(collapser)
        begin
            val = collapser.evaluate_as_constant(self).as(Constant)
            return Constant.new(val.@value, bitwidth: @bitwidth)
        rescue ex : NonconstantExpression
            new_obj = self.dup
            new_obj.set_operand!(collapser.lookup(@expr))
            return new_obj
        end
    end

    def_equals @op, @expr
    def_hash @op, @expr
end

abstract class BitWidthCast < UnaryOp
    def initialize (op : ::Symbol, expr : DFGExpr, new_bitwidth : BitWidth)
        super(op, expr, new_bitwidth)
    end

    def self.bake (expr : DFGExpr, new_bitwidth : BitWidth)
        if expr.is_a? Constant
            value = self.static_eval(
                expr.@value,
                old_bitwidth: expr.@bitwidth,
                new_bitwidth: new_bitwidth)
            Constant.new(value, bitwidth: new_bitwidth)
        else
            self.new(expr, bitwidth: new_bitwidth)
        end
    end
end

# Logical-Not unary operation
class LogicalNot < UnaryOp
    def initialize (@expr)
        super(:lnot, @expr)
    end

    def evaluate (collapser)
        return !collapser.lookup(@expr)
    end
end

# Bitwise-Not unary operation
class BitNot < UnaryOp
    # TODO - handle bit widths here
    def initialize(@expr)#, @bit_width)
        super(:bitnot, @expr)
    end

    def evaluate(collapser)
        #return (~collapser.lookup(@expr) & @bit_width.get_neg1()
    end
end

# Negate unary operation
class Negate < UnaryOp
    def initialize (@expr)
        super(:negate, @expr)
    end

    def evaluate (collapser)
        return -collapser.lookup(@expr).as(Constant).@value
    end
end

# Zero-extend operation
class ZeroExtend < BitWidthCast
    def initialize (@expr, bitwidth)
        super(:zext, @expr, bitwidth)
    end

    def self.static_eval (value, old_bitwidth, new_bitwidth)
        value
    end
end

# Sign-extend operation
class SignExtend < BitWidthCast
    def initialize (@expr, bitwidth)
        super(:zext, @expr, bitwidth)
    end

    def self.static_eval (value, old_bitwidth, new_bitwidth)
        old_bitwidth.sign_extend_to(value.to_u64!, new_bitwidth).to_i64!
    end
end

# Truncate to a smaller bit width operation
class Truncate < BitWidthCast
    def initialize (@expr, bitwidth)
        super(:trunc, @expr, bitwidth)
    end

    def self.static_eval (value, old_bitwidth, new_bitwidth)
        return new_bitwidth.truncate(value.to_u64!).to_i64!
    end
end

end
