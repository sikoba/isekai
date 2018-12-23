# Operators on DFGExpressions. Wraps the operation in a type-safe manner.
class DFGOperator
end

class LeftShiftOp < DFGOperator
    def initialize (@bitwidth : Int32)
    end
end

class RightShiftOp < DFGOperator
    def initialize (@bitwidth : Int32)
    end
end

class LogicalAndOp < DFGOperator
end

class OperatorAdd < DFGOperator
end

class OperatorSub < DFGOperator
end

class OperatorMul < DFGOperator
end

class OperatorDiv < DFGOperator
end

class OperatorMod < DFGOperator
end

class OperatorXor < DFGOperator
end

class OperatorBor < DFGOperator
end

class OperatorBAnd < DFGOperator
end
