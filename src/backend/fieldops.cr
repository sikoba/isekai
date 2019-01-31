require "./wire"

module Isekai
    # Note: FieldOps don't contain any logic by themselves. They just contain the
    # definition that's output in the output file.

    # Abstract Field Operation's "gate". Contains the set
    # of inputs, outputs and a field command - a string describing
    # the gate which is output to the circuit file
    abstract class FieldOp
        def initialize (@comment : String)
        end

        abstract def field_command()
        abstract def input_wires()
        abstract def output_wires()

        def to_s(io)
            io << "#{field_command()} # #{@comment}"
        end
    end

    # An base for the input gate. Has no input wires, only the outputs.
    class FieldInputBase < FieldOp
        def initialize (@command : String, @comment, @out_wire : Wire)
            super(@comment)
        end

        def field_command
            return "#{@command} #{@out_wire.to_s()}"
        end

        def input_wires
            return WireList.new()
        end

        def output_wires
            return WireList.new([@out_wire])
        end
    end
    
    # A concrete "input" gate - only specifies the command for FieldInputBase
    class FieldInput < FieldInputBase
        def initialize (@comment, @out_wire : Wire)
            super("input", @comment, @out_wire)
        end
    end

    # A concrete nizk "input" gate - only specifies the command for FieldInputBase
    class FieldNIZKInput < FieldInputBase
        def initialize (@comment, @out_wire : Wire)
            super("nizkinput", @comment, @out_wire)
        end
    end

    # An output gate. Only contains input wires.
    class FieldOutput < FieldOp
        def initialize (@comment, @in_wire : Wire)
            super(@comment)
        end

        def field_command
            return "output #{@in_wire}"
        end

        def input_wires
            return WireList.new([@in_wire])
        end

        def output_wires
            return WireList.new()
        end
    end
end