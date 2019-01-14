require "spec"
require "../src/dfg.cr"
require "../src/dfgoperator.cr"

describe Isekai do
    op : Isekai::DFGOperator = Isekai::OperatorAdd.new()
    op.evaluate(Isekai::Constant.new(1), Isekai::Constant.new(2)).should eq 3
    op = Isekai::OperatorMul.new()
    op.evaluate(Isekai::Constant.new(1), Isekai::Constant.new(2)).should eq 2
end
