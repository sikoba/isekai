require "./busreq.cr"
require "./bus.cr"
require "./booleanbusreq.cr"
require "./booleanfieldops"
require "math"

module Isekai::Backend
    # boolean bitwise input bus.
    class BooleanInputBus < BooleanBus
        @used : Bool?
        @width : Int32

        def initialize (@board, @input_idx : Int32)
            super(@board, Constants::MAJOR_INPUT)
            set_order(@input_idx)
            @used = nil
            @width = @board.bit_width.get_width()
        end

        def set_used (used)
            @used = used
        end

        def get_trace_count
            return @width
        end

        def get_wire_count
            return @width
        end

        def do_trace (i)
            return @wire_list.as(WireList)[i]
        end

        def get_field_ops
            cmds = Array(FieldOp).new()

            (0..@width-1).each do |i|
                comment = "bit #{i} of input #{@input_idx}"
                if @used == false
                    comment += " (unused)"
                end

                cmds << FieldInput.new(comment, @wire_list.as(WireList)[i])
            end

            return cmds
        end
    end

    # Boolean zero.
    class BooleanZero < BooleanBus
        def initialize (@board)
            super(@board, Constants::MAJOR_LOGIC)
        end

        def get_trace_count
            return 1
        end
        
        def get_wire_count
            return 1
        end

        def do_trace (i)
            return @wire_list.as(WireList)[0]
        end

        # implement zero using XOR(1,1)
        def get_field_ops
            return [
                FieldXor.new("zero", @board.one_wire(), @board.one_wire(), @wire_list.as(WireList)[0])
            ]
        end
    end

    # boolean output bus.
    class BooleanOutputBus < BooleanBus
        @width : Int32

        def initialize (@board, @bus_in : Bus, @output_idx : Int32)
            super(@board, Constants::MAJOR_OUTPUT)
            @width = @board.bit_width.@width
        end

        def get_trace_count
            return @width
        end

        def get_wire_count
            return @width
        end

        # Implements output as Xor every bit with 0.
        def get_field_ops
            cmds = Array(FieldOp).new()

            (0..@width-1).each do |i|
                comment = "bit #{i} of output #{@output_idx}"
                out_wire = @wire_list.as(WireList)[i]

                cmds << FieldXor.new(comment,
                    @board.zero_wire(), @bus_in.get_trace(i), out_wire)
                cmds << FieldOutput.new(comment, out_wire)
            end

            return cmds
        end

        def do_trace(i)
            raise "Not implemented."
        end
    end

    # Implements adder.
    class BooleanAddBus < BooleanBus
        @trace_count : Int32
        def initialize (@board, @bus_left : Bus, @bus_right : Bus)
            super(@board, Constants::MAJOR_LOGIC)
            @trace_count = Math.max(@bus_left.get_trace_count(), @bus_right.get_trace_count()) + 1
        end

        def get_trace_count
            return @trace_count
        end

        def get_wire_count
            return 5 * @trace_count
        end

        # Lays down adders  with carry (implemented with Xor and And gates) for each trace.
        def get_field_ops
            cmds = Array(FieldOp).new()

            (0..@trace_count-1).each do |i|
                xiw  = @bus_left.get_trace(i)
                yiw  = @bus_right.get_trace(i)

                if (i==0)
                    carryw = @board.zero_wire()
                else
                    carryw = @wire_list.as(WireList)[(i-1)*5+4]
                end

                xxw  = @wire_list.as(WireList)[i*5+0]
                yxw  = @wire_list.as(WireList)[i*5+1]
                andw = @wire_list.as(WireList)[i*5+2]
                sxw  = @wire_list.as(WireList)[i*5+3]
                cxw  = @wire_list.as(WireList)[i*5+4]
                nm = @wire_list.as(WireList)[0]
                cmds << FieldXor.new("add (#{nm}  xx#{i}", xiw, carryw, xxw)
                cmds << FieldXor.new("add (#{nm}  yx#{i}", yiw, carryw, yxw)
                cmds << FieldAnd.new("add (#{nm} and#{i}", xxw, yxw, andw)
                cmds << FieldXor.new("add (#{nm}  sx#{i}", xiw, yxw, sxw)
                cmds << FieldXor.new("add (#{nm}  cx#{i}", carryw, andw, cxw)
            end

            return cmds
        end

        def do_trace(i)
            if i == @trace_count-1
                return @wire_list.as(WireList)[-1]
            else
                return @wire_list.as(WireList)[i * 5 + 3]
            end
        end
    end

    # Bus that check if all inputs are 1 - implemented as AND(input(0), input(1))
    class AllOnesBus < AllOnesBase   
        def and_field_op(comment, inputs, outputs)
            return FieldAnd.new(comment, inputs[0], inputs[1], outputs[0])
        end
    end

    # Basic bus for bitwise ops.
    abstract class BitWiseBus < BinaryBooleanBus
        def initialize(@board, @bus_left, @bus_right, @comment_name : String)
            super(@board, @bus_left, @bus_right)
        end

        def comment_name()
            return @comment_name
        end

        def get_wire_count
            return get_trace_count()
        end
    
        def do_trace(i)
            return @wire_list.as(WireList)[i]
        end
    end
    
    # Bitwise AND, yields AND gate for every bit pair
    class BoolBitAndBus < BitWiseBus
        def initialize(@board, *buses)
            super(@board, buses[0], buses[1], "bitand")
        end

        def get_field_ops
            cmds = Array(FieldOp).new()

            (0..get_trace_count-1).each do |i|
                comment = "#{comment_name} bit #{i}"
                cmds << FieldAnd.new(comment,
                    @bus_left.get_trace(i),
                    @bus_right.get_trace(i),
                    @wire_list.as(WireList)[i])
            end
            return cmds
        end
    
    end

    # Bitwise OR, yields OR gate for every bit pair
    class BitOrBus < BitWiseBus
        def initialize(@board, @bus_left, @bus_right)
            super(@board, @bus_left, @bus_right, "bitor")
        end


        def get_field_ops
            cmds = Array(FieldOp).new()

            (0..get_trace_count-1).each do |i|
                comment = "#{comment_name} bit #{i}"
                cmds << FieldOr.new(comment,
                    @bus_left.get_trace(i),
                    @bus_right.get_trace(i),
                    @wire_list.as(WireList)[i])
            end
            return cmds
        end
    
    end

    # Bitwise XOR, yields an XOR gate for every bit pair
    class XorBus < BitWiseBus
        def initialize(@board, @bus_left, @bus_right)
            super(@board, @bus_left, @bus_right, "xor")
        end


        def get_field_ops
            cmds = Array(FieldOp).new()

            (0..get_trace_count()-1).each do |i|
                comment = "#{comment_name} bit #{i}"
                cmds << FieldXor.new(comment,
                    @bus_left.get_trace(i),
                    @bus_right.get_trace(i),
                    @wire_list.as(WireList)[i])
            end
            return cmds
        end
    
    end
end
