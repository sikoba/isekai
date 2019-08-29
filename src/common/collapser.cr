require "./common.cr"
require "./dfg.cr"
require "./bitwidth.cr"

module Isekai

abstract class Collapser(ExprType, ReducedType)
    def initialize()
        @table = Hash(ExprType, (Constant|ReducedType)).new()
    end

    abstract def get_dependencies(key) : Array(ExprType)
    abstract def collapse_impl(key)

    def collapse_tree(key : ExprType)
        stack = Array(ExprType).new()
        stack.push(key)

        while stack.size() > 0
            key = stack[-1]
            # Check if we already collapsed this
            if @table[key]?
                stack.pop()
                next
            end

            # get all dependencies for this expression
            deps : Array(ExprType) = get_dependencies(key)
            raise "Can't get dependencies" if deps.is_a? Nil
            
            new_deps = Array(ExprType).new()

            deps.each do |key|
                if !@table[key]?
                    new_deps.push(key)
                end
            end


            # filter out all dependencies that we already resolved
            # if there are no unresolved dependencies anymore
            # collapse this and store it
            if new_deps.size() == 0
                stack.pop()
                res = collapse_impl(key)

                if ReducedType.is_a? DFGExpr
                    if res.is_a? Int64
                        res = Constant.new(res, bitwidth: BitWidth.new_for_undefined)
                    end
                    if res.is_a? Bool
                        res = Constant.new(res ? 1_i64 : 0_i64, bitwidth: BitWidth.new_for_undefined)
                    end
                end

                if res
                    @table[key] = res
                else
                    raise "Can't convert #{res} to DFGExpr"
                end
            else
                # go on and calculate all dependencies first
                stack += new_deps
            end

        end

        return @table[key].as(ReducedType)
    end

    def lookup (key)
        return @table[key].as(ReducedType)
    end
end

# Expression evaluator - evaluates the expression to scalar
# constants
class ExpressionEvaluator(ExprType, ReducedType) < Collapser(ExprType, ReducedType)
    def get_dependencies(expr)
        return expr.collapse_dependencies()
    end

    def collapse_impl(expr)
        evaluate = expr.evaluate(self)
        if evaluate.is_a? Int64
            return Constant.new(evaluate, bitwidth: BitWidth.new_for_undefined)
        elsif evaluate.is_a? Bool
            if evaluate
                return Constant.new(1, bitwidth: BitWidth.new_for_undefined)
            else 
                return Constant.new(0, bitwidth: BitWidth.new_for_undefined)
            end 
        else
            return evaluate.as(ReducedType)
        end
    end 

    def get_input(key)
        raise NonconstantExpression.new()
    end
end


# Expression collapser - evaluates the expression to their minimal
# form (with no dependency expressions that are consisted only of constants)
class ExpressionCollapser(ExprType, ReducedType) < Collapser(ExprType, ReducedType)
    def initialize (@expr_evaluator : ExpressionEvaluator(ExprType, ReducedType))
        super()
    end

    def get_dependencies (expr)
        return expr.collapse_dependencies()
    end

    def collapse_impl(expr)
        return expr.collapse_constants(self).as(ReducedType)
    end

    def evaluate_as_constant(expr)
        const = @expr_evaluator.collapse_tree(expr)
        raise NonconstantExpression.new("Can't resolve #{expr} as constant") unless const.is_a? Constant
        return const.as Constant
    end
end
end
