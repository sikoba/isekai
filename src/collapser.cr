require "dfg.cr"

abstract class Collapser
    def initialize()
        @table = Set(DFGExpr).new()
    end

    abstract def get_dependencies(key)
    abstract def collapse_impl(key)

    def collapse_tree(key : DFGExpr) : DFGExpr
        stack = Array(DFGExpr).new()
        stack.push(key)

        while stack.size() > 0
            key = stack[-1]

            # Check if we already collapsed this
            if key in @table
                stack.pop()
                next
            end

            # get all dependencies for this expression
            deps = get_dependencies(key)

            # filter out all dependencies that we already resolved
            new_deps = deps.select { |key| return (! key in @table) }

            # if there are no unresolved dependencies anymore
            # collapse this and store it
            if new_deps.size() == 0
                stack.pop()
                @table[key] = collapse_impl(key)
            else
                # go on and calculate all dependencies first
                stack.push(new_deps)
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
end


# Expression collapser - evaluates the expression to their minimal
# form (with no dependency expressions that are consisted only of constants)
class ExpressionCollapser < Collapser
    def initialize (@expr_evaluator : ExpressionEvaluator)
    end

    def get_dependencies (expr)
        return expr.collapse_dependencies()
    end

    def collapse_impl(expr)
        return expr.collapse_constants()
    end

    def evaluate_as_constant(expr)
        @expr_evaluator.collapse_tree(expr)
    end
end