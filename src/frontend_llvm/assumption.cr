require "../common/dfg"

module Isekai::LLVMFrontend

struct Assumption
    @chain = [] of Tuple(DFGExpr, Bool)

    def initialize ()
    end

    private def conditionalize_impl (
            old_expr : DFGExpr,
            new_expr : DFGExpr,
            chain_index : Int32) : DFGExpr

        if old_expr.is_a? Conditional && chain_index != @chain.size
            cond, flag = @chain[chain_index][0], @chain[chain_index][1]
            if cond.same?(old_expr.@cond)
                valtrue, valfalse = old_expr.@valtrue, old_expr.@valfalse
                if flag
                    valtrue = conditionalize_impl(valtrue, new_expr, chain_index + 1)
                else
                    valfalse = conditionalize_impl(valfalse, new_expr, chain_index + 1)
                end
                return Conditional.new(cond, valtrue, valfalse)
            end
        end

        result = new_expr
        (chain_index...@chain.size).reverse_each do |i|
            cond, flag = @chain[i][0], @chain[i][1]
            if flag
                result = Conditional.new(cond, result, old_expr)
            else
                result = Conditional.new(cond, old_expr, result)
            end
        end
        return result
    end

    def conditionalize (old_expr : DFGExpr, new_expr : DFGExpr) : DFGExpr
        return conditionalize_impl(old_expr, new_expr, chain_index: 0)
    end

    def reduce (expr : DFGExpr) : DFGExpr
        @chain.each do |(cond, flag)|
            break unless expr.is_a? Conditional
            break unless cond.same?(expr.@cond)
            expr = flag ? expr.@valtrue : expr.@valfalse
        end
        return expr
    end

    def push (cond : DFGExpr, flag : Bool)
        @chain << {cond, flag}
        self
    end

    def pop (n = 1)
        @chain.pop(n)
        self
    end

    def empty?
        return @chain.empty?
    end
end

end
