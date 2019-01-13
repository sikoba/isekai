require "spec"
require "../src/dfg.cr"
require "../src/dfgoperator.cr"

describe Isekai do
    op : DFGOperator = OperatorAdd.new()
    op.evaluate(1, 2).should eq 3
    op = OperatorMul.new()
    op.evaluate(1, 2).should eq 2
end
