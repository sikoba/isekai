require "spec"
require "../src/collapser.cr"
require "../src/dfg.cr"

describe Isekai do
    five = Isekai::Constant.new(5)
    four = Isekai::Constant.new(4)
    add_expr = Isekai::Add.new(five, four)

    # evaluate the expression
    expr_eval = Isekai::ExpressionEvaluator.new()
    expr_collapser = Isekai::ExpressionCollapser.new(expr_eval)

    evaluated = expr_collapser.collapse_tree(add_expr)
    (evaluated.as Isekai::Constant).@value.should eq 9
end
