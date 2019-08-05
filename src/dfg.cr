require "./frontend/types.cr"
require "./frontend/storage.cr"
require "./dfgoperator"

private macro def_simplify_left(**kwargs)
    def self.simplify_left(const, right)
        {% for key, value in kwargs %}
            {% if key == :identity %}
                if const.@value == {{ value }}
                    return right
                end
            {% elsif key == :const %}
                if const.@value == {{ value[:match] }}
                    return Constant.new( {{ value[:result] }} )
                end
            {% else %}
                {% raise "Invalid keyword argument" %}
            {% end %}
        {% end %}
        return self.new(const, right)
    end
end

private macro def_simplify_right(**kwargs)
    def self.simplify_right(left, const)
        {% for key, value in kwargs %}
            {% if key == :identity %}
                if const.@value == {{ value }}
                    return left
                end
            {% elsif key == :const %}
                if const.@value == {{ value[:match] }}
                    return Constant.new( {{ value[:result] }} )
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
class DFGExpr < SymbolTableValue
    #add_object_helpers

    def collapse_dependencies()
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
    #add_object_helpers
end

# Undefined operation. Raised if the operation is not supported.
class Undefined < DFGExpr
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

class Structure < DFGExpr
    def initialize(@storage : Storage)
    end
end

# Abstract operation
class Op < DFGExpr
    #add_object_helpers
end

class Field < Op
    def initialize(@key : StorageKey)
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

class Alloca < DFGExpr
    def initialize(@idx : Int32)
    end
end

class Deref < DFGExpr
    def initialize(@target : DFGExpr)
    end
end

class GetPointer < DFGExpr
    def initialize(@target : DFGExpr)
    end
end

# Operation on the array.
class ArrayOp < Op
    #add_object_helpers
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

    def initialize (@value : Int32)
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
class Conditional < Op
    #add_object_helpers
    def initialize (@cond : DFGExpr, @valtrue : DFGExpr, @valfalse : DFGExpr)
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
            return Constant.new(collapser.evaluate_as_constant(self).@value)
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
class BinaryOp < Op
    #add_object_helpers
    def initialize (@op : ::Symbol, @left : DFGExpr, @right : DFGExpr)
    end

    def set_operands(left, right)
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
        collapsed.set_operands(left, right)
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
class BinaryMath < BinaryOp
    ##add_object_helpers
    def initialize (@op, @crystalop : DFGOperator, @identity : (Int32|Nil), @left, @right)
        super(@op, @left, @right)
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

# Add operation
class Add < BinaryMath
    #add_object_helpers
    def initialize (@left, @right)
        super(:plus, OperatorAdd.new, 0, @left, @right)
    end

    def self.eval_with (left, right)
        left + right
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

    def self.eval_with (left, right)
        left * right
    end

    def_simplify_left identity: 1, const: {match: 0, result: 0}
    def_simplify_right identity: 1, const: {match: 0, result: 0}
end


# Subtract operation
class Subtract < BinaryMath
    def initialize (@left, @right)
        super(:minus, OperatorSub.new, 0, @left, @right)
    end

    def self.eval_with (left, right)
        left - right
    end

    def_simplify_left
    def_simplify_right identity: 0
end

# Divide operation
class Divide < BinaryMath
    def initialize (@left, @right)
        super(:divide, OperatorDiv.new, 1, @left, @right)
    end

    def self.eval_with (left, right)
        left / right
    end

    # 0 / x = 0
    def_simplify_left const: {match: 0, result: 0}
    # x / 1 = x
    def_simplify_right identity: 1
end

# Modulo operation
class Modulo < BinaryMath
    def initialize (@left, @right)
        super(:modulo, OperatorMod.new, 1, @left, @right)
    end

    def self.eval_with (left, right)
        left % right
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

    def self.eval_with (left, right)
        left ^ right
    end

    def_simplify_left identity: 0
    def_simplify_right identity: 0
end

# Left shift operation
class LeftShift < BinaryMath
    def initialize (@left, @right)
        super(:lshift, LeftShiftOp.new, 0, @left, @right)
    end

    def self.eval_with (left, right)
        left << right
    end

    # 0 << x = 0
    def_simplify_left const: {match: 0, result: 0}
    # x << 0 = x
    def_simplify_right identity: 0
end

# Right shift operation
class RightShift < BinaryMath
    def initialize (@left, @right)
        super(:rshift, RightShiftOp.new, 0, @left, @right)
    end

    def self.eval_with (left, right)
        left >> right
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

    def self.eval_with (left, right)
        left | right
    end

    def_simplify_left identity: 0
    def_simplify_right identity: 0
end

# bitwise-and operation
class BitAnd < BinaryMath
    def initialize (@left, @right)
        super(:bitand, OperatorBAnd.new, nil, @left, @right)
    end

    def self.eval_with (left, right)
        left & right
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

# Less-than compare operation
class CmpLT < BinaryOp
    def initialize (@left, @right)
        super(:lt, @left, @right)
    end

    def evaluate(collapser)
        begin
            return collapser.lookup(@left).as(Constant).@value < collapser.lookup(@right).as(Constant).@value
        rescue
            raise NonconstantExpression.new("can't evaluate #{@left} >= #{@right}")
        end
    end

    def self.eval_with (left, right)
        (left < right) ? 1 : 0
    end

    def_simplify_left
    def_simplify_right
end

# Less-than-or-equal compare operation
class CmpLEQ < BinaryOp
    def initialize (@left, @right)
        super(:leq, @left, @right)
    end

    def evaluate(collapser)
        begin
            return collapser.lookup(@left).as(Constant).@value <= collapser.lookup(@right).as(Constant).@value
        rescue
            raise NonconstantExpression.new("can't evaluate #{@left} <= #{@right}")
        end
    end

    def self.eval_with (left, right)
        (left <= right) ? 1 : 0
    end

    def_simplify_left
    def_simplify_right
end

# Equal compare operation
class CmpEQ < BinaryOp
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

    def self.eval_with (left, right)
        (left == right) ? 1 : 0
    end

    def_simplify_left
    def_simplify_right
end

# Not-equal compare operation
class CmpNEQ < BinaryOp
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

    def self.eval_with (left, right)
        (left != right) ? 1 : 0
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
class UnaryOp < Op
    #add_object_helpers

    @expr : (Isekai::DFGExpr)?
    setter expr : DFGExpr

    def initialize (@op : ::Symbol, @expr : DFGExpr)
    end

    def collapse_dependencies() : Array(DFGExpr)
        if expr = @expr
            return Array(DFGExpr).new().push(expr)
        else
            raise "No expression set"
        end
    end

    def collapse_constants(collapser)
        begin
            val = collapser.evaluate_as_constant(self).as(Constant)
            return Constant.new(val.@value)
        rescue ex : NonconstantExpression
            new_obj = self.dup
            new_obj.expr = collapser.lookup(@expr)
            return new_obj
        end
    end

    def_equals @op, @expr
    def_hash @op, @expr
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

    def self.eval_with (value)
        ~value
    end

    def evaluate(collapser)
        #return (~collapser.lookup(@expr) & @bit_width.get_neg1()
    end
end

# Negate unary operation
class Negate < UnaryOp
    def initialize(@expr)
        super(:negate, @expr)
    end

    def evaluate(collapser)
        return -collapser.lookup(@expr).as(Constant).@value
    end

    def self.eval_with (value)
        return -value
    end
end

def self.dfg_make_binary (klass, left, right)
    if left.is_a? Constant
        if right.is_a? Constant
            Constant.new(klass.eval_with(left.@value, right.@value))
        else
            klass.simplify_left(left, right)
        end
    elsif right.is_a? Constant
        klass.simplify_right(left, right)
    else
        klass.new(left, right)
    end
end

def self.dfg_make_unary (klass, operand)
    if operand.is_a? Constant
        Constant.new(klass.eval_with(operand))
    else
        klass.new(operand)
    end
end

def self.dfg_make_conditional (cond, valtrue, valfalse)
    if cond.is_a? Constant
        (cond.@value != 0) ? valtrue : valfalse
    else
        Conditional.new(cond, valtrue, valfalse)
    end
end

end
