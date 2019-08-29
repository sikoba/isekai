require "../common/dfg"

module Isekai::AltBackend

def self.lay_down_output (backend, output : DFGExpr) : Nil
    stack = [{output, false}]
    until stack.empty?
        expr, ready = stack.pop
        unless ready
            unless backend.has_cached?(expr)
                stack << {expr, true}
                backend.visit_dependencies(expr) { |dep| stack << {dep, false} }
            end
        else
            backend.lay_down_and_cache(expr)
        end
    end
    backend.add_output_cached!(output)
end

end
