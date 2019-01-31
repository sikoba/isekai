require "./wire"
require "./fieldops"

module Isekai
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