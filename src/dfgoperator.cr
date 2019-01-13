# Operators on DFGExpressions. Wraps the operation in a type-safe manner.
abstract class DFGOperator
    abstract def evaluate (left : T, right : T) forall T
end

class LeftShiftOp < DFGOperator
    def initialize (@bitwidth : Int32)
    end

    def evaluate (left : T, right : T) forall T
        return left << right
    end
end

class RightShiftOp < DFGOperator
    def initialize (@bitwidth : Int32)
    end

    def evaluate (left : T, right : T) forall T
        return left >> right
    end
end

class LogicalAndOp < DFGOperator
    def evaluate (left : T, right : T) forall T
        return left && right
    end
end

class OperatorAdd < DFGOperator
    def evaluate (left : T, right : T) forall T
        return left + right
    end
end

class OperatorSub < DFGOperator
    def evaluate (left : T, right : T) forall T
        return left - right
    end
end

class OperatorMul < DFGOperator
    def evaluate (left : T, right : T) forall T
        return left * right
    end
end

class OperatorDiv < DFGOperator
    def evaluate (left : T, right : T) forall T
        return left / right
    end
end

class OperatorMod < DFGOperator
    def evaluate (left : T, right : T) forall T
        return left % right
    end
end

class OperatorXor < DFGOperator
    def evaluate (left : T, right : T) forall T
        return left ^ right
    end
end

class OperatorBor < DFGOperator
    def evaluate (left : T, right : T) forall T
        return left | right
    end
end

class OperatorBAnd < DFGOperator
    def evaluate (left : T, right : T) forall T
        return left & right
    end
end