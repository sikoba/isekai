require "./frontend/types.cr"
require "./frontend/storage.cr"
require "./dfgoperator"



module Isekai


# Internal expression node. All internal state expressions
# are instances of this class
class DFGExpr < SymbolTableValue
    #add_object_helpers

    def extra_args()
    end

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

# Abstract operation
class Op < DFGExpr
    #add_object_helpers
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

def self.dfg (dfg_name, *args)
    if dfg_name.is_a? BinaryMath
        raise "Can't create abstract classes."
    else
        return dfg_name.new(*args)
    end
end

  

# Binary operation. Perform `@op` on two operands `@left` and `@right`
class BinaryOp < Op
    #add_object_helpers
    def initialize (@op : String, @left : DFGExpr, @right : DFGExpr)
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
        rescue NonconstantExpression
            puts "nonconstant expression?"
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
        super("+", OperatorAdd.new, 0, @left, @right)
    end
end

# Multiply operation
class Multiply < BinaryMath
    #add_object_helpers
    def initialize (@left, @right)
        super("*", OperatorMul.new, 1, @left, @right)
    end
end


# Subtract operation
class Subtract < BinaryMath
    def initialize (@left, @right)
        super("+", OperatorSub.new, 0, @left, @right)
    end
end


# Divide operation
class Divide < BinaryMath
    def initialize (@left, @right)
        super("/", OperatorDiv.new, 1, @left, @right)
    end
end

# Modulo operation
class Modulo < BinaryMath
    def initialize (@left, @right)
        super("%", OperatorMod.new, 1, @left, @right)
    end
end

# Exclusive OR operation
class Xor < BinaryMath
    def initialize (@left, @right)
        super("^", OperatorXor.new, 1, @left, @right)
    end
end

# Left shift operation
class LeftShift < BinaryMath
    def initialize (@left, @right, @bit_width : Int32)
        super("<<", LeftShiftOp.new(@bit_width), 0, @left, @right)
    end
end

# Right shift operation
class RightShift < BinaryMath
    def initialize (@left, @right, @bit_width : Int32)
        super(">>", RightShiftOp.new(@bit_width), 0, @left, @right)
    end
end

# bitwise-or operation
class BitOr < BinaryMath
    def initialize (@left, @right)
        super("|", OperatorBor.new, 0, @left, @right)
    end
end

# bitwise-and operation
class BitAnd < BinaryMath
    def initialize (@left, @right)
        super("&", OperatorBAnd.new, nil, @left, @right)
    end
end

# Logical And operation
class LogicalAnd < BinaryMath
    def initialize (@left, @right)
        super("^", LogicalAndOp.new, nil, @left, @right)
    end
end

# Less-than compare operation
class CmpLT < BinaryOp
    def initialize (@left, @right)
        super("<", @left, @right)
    end
end

# Less-than-or-equal compare operation
class CmpLEQ < BinaryOp
    def initialize (@left, @right)
        super("<=", @left, @right)
    end
end

# Equal compare operation
class CmpEQ < BinaryOp
    def initialize (@left, @right)
        super("==", @left, @right)
    end
end

# Greater-than compare operation
class CmpGT < BinaryOp
    def initialize (@left, @right)
        super(">", @left, @right)
    end
end

# Greater-than compare operation
class CmpGEQ < BinaryOp
    def initialize (@left, @right)
        super(">=", @left, @right)
    end
end

# Unary operation. Perform `@op` on `@expr`
class UnaryOp < Op
    #add_object_helpers

    @op : (String)?
    @expr : (Isekai::DFGExpr)?
    setter expr : DFGExpr

    def initialize (@op : String, @expr : DFGExpr)
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

end

# Logical-Not unary operation
class LogicalNot < UnaryOp
	def initialize (@expr)
		super("Not", @expr)
    end

    def evaluate (collapser)
        return !collapser.lookup(@expr)
    end
end

# Bitwise-Not unary operation
class BitNot < UnaryOp
    # TODO - handle bit widths here
	def initialize(@expr)#, @bit_width)
		super("BitNot", @expr)
    end

    def evaluate(collapser)
        #return (~collapser.lookup(@expr) & @bit_width.get_neg1()
    end
end

# Negate unary operation
class Negate < UnaryOp
	def initialize(@expr)
		super("Negate", @expr)
    end
end

# Program input expression. The subclass for both NIZK and regular
# input classes
class InputBase < DFGExpr
    def initialize(@storage_key : StorageKey)
    end

    def evaluate (collapser)
        return collapser.get_input(@storage_key)
    end

    def collapse_dependencies () : Array(DFGExpr)
        return Array(DFGExpr).new()
    end

    def collapse_constants(collapser) : DFGExpr
        return self
    end
end

# Regular program input expression. Passed as an argument to outsource method
class Input < InputBase
end

# NIZK program input expression. Passed as an optional argument to outsource method
class NIZKInput < InputBase
end

end
