require "./wire"

module Isekai
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
    
    class FieldInput < FieldInputBase
        def initialize (@comment, @out_wire : Wire)
            super("input", @comment, @out_wire)
        end
    end

    class FieldNIZKInput < FieldInputBase
        def initialize (@comment, @out_wire : Wire)
            super("nizkinput", @comment, @out_wire)
        end
    end

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