require "./wire"
require "./fieldops"

module Isekai::Backend
    # Note: FieldOps don't contain any logic by themselves. They just contain the
    # definition that's output in the output file.
    # Every line of the output file contains a fieldOp object in the following form:
    # <command> in <in wires> out <out_wires>


    class BinaryFieldOp < FieldOp
        def initialize (@comment, @left_wire : Wire, @right_wire : Wire, @out_wire : Wire, @gate : String)
            super(@comment)
        end

        def field_command
            input = input_wires()
            output = output_wires()
            return "#{@gate} in #{input} #{output}"
        end

        def input_wires
            return WireList.new([@left_wire, @right_wire])
        end

        def output_wires
            return WireList.new([@out_wire])
        end
    end

    class FieldNand < BinaryFieldOp
        def initialize (@comment, @left_wire : Wire, @right_wire : Wire, @out_wire : Wire)
            super(@comment, @left_wire, @right_wire, @out_wire, "nand")
        end
    end

    class FieldOr < BinaryFieldOp
        def initialize (@comment, @left_wire : Wire, @right_wire : Wire, @out_wire : Wire)
            super(@comment, @left_wire, @right_wire, @out_wire, "or")
        end
    end

    class FieldAnd < BinaryFieldOp
        def initialize (@comment, @left_wire : Wire, @right_wire : Wire, @out_wire : Wire)
            super(@comment, @left_wire, @right_wire, @out_wire, "and")
        end
    end

    class FieldXor < BinaryFieldOp
        def initialize (@comment, @left_wire : Wire, @right_wire : Wire, @out_wire : Wire)
            super(@comment, @left_wire, @right_wire, @out_wire, "xor")
        end
    end
end
