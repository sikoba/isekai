require "spec"
require "../src/common/types.cr"

describe Isekai do
    fields = [Isekai::StructField.new(Isekai::IntType.new(), "a"),
              Isekai::StructField.new(Isekai::UnsignedType.new(), "b")]
    my_struct = Isekai::StructType.new("my_struct", fields)

    exp_size = (Isekai::IntType.new().sizeof + Isekai::UnsignedType.new().sizeof)
    my_struct.sizeof.should eq exp_size

    my_struct.offsetof("a").should eq 0
    my_struct.offsetof("b").should eq my_struct.get_field("a").@type.sizeof
end

