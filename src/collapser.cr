require "./dfg.cr"

module Isekai
abstract class Collapser
    def initialize()
        @table = Hash(DFGExpr, DFGExpr).new()
    end

    abstract def get_dependencies(key)
    abstract def collapse_impl(key)

    def collapse_tree(key)
        stack = Array(DFGExpr).new()
        stack.push(key)

        while stack.size() > 0
            key = stack[-1]
            # Check if we already collapsed this
            if @table[key]?
                stack.pop()
                next
            end

            # get all dependencies for this expression
            deps = get_dependencies(key)
            raise "Can't get dependencies" if deps.is_a? Nil
            
            new_deps = Array(DFGExpr).new()

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
                if res.is_a? Int32
                    res = Constant.new(res)
                end
                @table[key] = res
            else
                # go on and calculate all dependencies first
                stack += new_deps
            end

        end

        return @table[key]
    end

    def lookup (key)
        return @table[key]
    end
end

# Expression evaluator - evaluates the expression to scalar
# constants
class ExpressionEvaluator < Collapser
    def get_dependencies(expr)
        return expr.collapse_dependencies()
    end

    def collapse_impl(expr)
        return expr.evaluate(self)
    end 

    def get_input(key)
        raise NonconstantExpression.new()
    end
end


# Expression collapser - evaluates the expression to their minimal
# form (with no dependency expressions that are consisted only of constants)
class ExpressionCollapser < Collapser
    def initialize (@expr_evaluator : ExpressionEvaluator)
        super()
    end

    def get_dependencies (expr)
        return expr.collapse_dependencies()
    end

    def collapse_impl(expr)
        return expr.collapse_constants(self)
    end

    def evaluate_as_constant(expr)
        return @expr_evaluator.collapse_tree(expr)
    end
end
end