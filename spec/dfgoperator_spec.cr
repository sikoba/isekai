require "spec"
require "../src/common/dfg.cr"
require "../src/common/dfgoperator.cr"

describe Isekai do
    bw = Isekai::BitWidth.new(32);
    op : Isekai::DFGOperator = Isekai::OperatorAdd.new()
    op.evaluate(Isekai::Constant.new(1, bw), Isekai::Constant.new(2, bw)).should eq 3
    op = Isekai::OperatorMul.new()
    op.evaluate(Isekai::Constant.new(1, bw), Isekai::Constant.new(2, bw)).should eq 2
end
