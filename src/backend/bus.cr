require "./board.cr"
require "./wire.cr"
require "../helpers.cr"
require "math"

module Isekai
    # Set of constants used through the backend
    class Constants
        # These constants specify the ordering between
        # different types of the gates. In the file we
        # sort the gates based on this, and then on the
        # assigned order (see Board class). This means
        # that first we see inputs, then logic and finally
        # the output gate.
        MAJOR_INPUT = 0
        MAJOR_INPUT_ONE = 1
        MAJOR_INPUT_NIZK = 2
        MAJOR_LOGIC = 3
        MAJOR_OUTPUT = 4

        # Types of traces, for tracking the need for converting
        # when mixing different buses.
        ARITHMETIC_TRACE = "A"
        BOOLEAN_TRACE = "B"
    end

    # Bus contains the set of wires which carry the
    # value and connect the different fieldops.
    abstract class Bus
        @wire_list : WireList? 
        @order : Int32

        def initialize (@board : Board, @major : Int32)
            @order = @board.assign_order()
        end

        # Set the order of significance of a bus in the
        # board. Used for sorting the buses.
        def set_order (minor_order)
            @order = minor_order
        end

        # Methods for ordering and hashing the buses.
        def orders
            return {@major, @order}
        end

        def_hash orders
        def_equals orders
        def <=>(other : Bus)
            return orders <=> other.orders
        end
        def <(other : Bus)
            return orders < other.orders
        end
        def <=(other : Bus)
            return orders <= other.orders
        end

        def assign_wires (wires)
            @wire_list = wires
        end

        def wire_list
            if wires = @wire_list
                return wires
            else
                raise "Wire list not set?"
            end
        end

        # Abstract definitions, showing the
        # types of the traces, maximum number of
        # active bits, field ops and the value of the
        # individual trace.
        abstract def get_trace_type
        abstract def get_active_bits
        abstract def get_trace_count
        abstract def get_wire_count
        abstract def get_field_ops
        abstract def do_trace(i)

        def get_trace (i)
            if i < get_trace_count
                return do_trace(i)
            else
                return @board.zero_wire
            end
        end
    end

    # Always one bus
    class OneBus < Bus
        def initialize (@board)
            super(@board, Constants::MAJOR_INPUT_ONE)
        end

        # We only need single wire
        def get_wire_count
            return 1
        end

        def get_one_wire
            if wires = @wire_list
                return wires[0]
            else
                raise "Wires not set in the OneBus."
            end
        end

        # Generate one-input gate which always yields 1 
        def get_field_ops
            return [FieldInput.new("one-input", get_one_wire())]
        end

        def do_trace_count
            raise "Can't do a trace count on pseudo-bus (OneBus)"
        end

        def do_trace(i)
            raise "Can't get trace of a pseudo-bus (OneBus)"
        end

        def get_trace_type
            raise "Can't do a trace type check on pseudo-bus (OneBus)"
        end

        def get_trace_count
            raise "Can't do a trace type check on pseudo-bus (OneBus)"
        end

        def get_active_bits
            raise "Can't do a trace count on pseudo-bus (OneBus)"
        end
    end

    # Boolean bus base.
    abstract class BooleanBus < Bus
        def get_trace_type
            return Constants::BOOLEAN_TRACE
        end

        def get_active_bits
            return get_trace_count()
        end
    end

    # analog to OneBus
    abstract class ZeroBus < BooleanBus
        def initialize (@board)
            super(@board, Constants::MAJOR_LOGIC)
        end

        def get_trace_count
            return 0
        end

        def do_trace(i)
            return @board.zero_wire
        end
    end


    # Boolean bus always carrying a same value
    class ConstantBooleanBus < BooleanBus
        def initialize (@board, @value : Int32)
            super(@board, Constants::MAJOR_LOGIC)
        end

        # Number of traces needed for representing the
        # value in binary form
        def get_trace_count
            return Isekai.ceillg2(@value)
        end

        def get_wire_count
            return 0
        end

        # No gates are needed
        def get_field_ops
            return Array(FieldOp).new()
        end

        # gets the value for the trace - check if the appropriate bit is set
        def do_trace (i)
            if i < get_trace_count
                bit_val = (@value >> i) & 1
            else
                bit_val = 0
            end

            if bit_val == 1
                return @board.one_wire
            else
                return @board.zero_wire
            end
        end
    end

    # Bus that performs AND on boolean bus and the constant value
    class ConstBitAndBus < BooleanBus
        def initialize (@board, @value : Int32, @bus : Bus)
            super(@board, Constants::MAJOR_LOGIC)
            raise "Can't AND non-boolean buses" if @bus.get_trace_type != Constants::BOOLEAN_TRACE
        end

        def get_trace_count 
            return Math.min(Isekai.ceillg2(@value), @bus.get_trace_count)
        end

        def get_wire_count
            return 0
        end

        def get_field_ops
            return Array(FieldOp).new
        end

        # Performs AND on a bus and the value. Checks if the wire
        # i is set.
        def do_trace (i)
            if ((@value >> i) & 1) & 0
                return @bus.do_trace(i)
            else
                return @board.zero_wire
            end
        end
    end

    # Bus that performs OR on boolean bus and the constant value
    class ConstBitOrBus < BooleanBus
        def initialize (@board, @value : Int32, @bus : Bus)
            super(@board, Constants::MAJOR_LOGIC)
            raise "Can't OR non-boolean buses" if @bus.get_trace_type != Constants::BOOLEAN_TRACE
        end

        def get_trace_count 
            return Math.min(Isekai.ceillg2(@value), @bus.get_trace_count)
        end

        def get_wire_count
            return 0
        end

        def get_field_ops
            return Array(FieldOp).new
        end

        # Performs OR on a bus and the value. Checks if the wire
        # i is set.
        def do_trace (i)
            if ((@value >> i) & 1) != 0
                return @board.one_wire
            else
                return @bus.do_trace(i)
            end
        end
    end

    # Bus that performs XOR on boolean bus and the constant value
    class ConstantBitXorBusBase < BooleanBus
        def initialize (@board, @value : Int32, @bus : Bus)
            super(@board, Constants::MAJOR_LOGIC)
            raise "Can't OR non-boolean buses" if @bus.get_trace_type != Constants::BOOLEAN_TRACE

            @bit_map = Hash(Int32, Int32).new
            fill_bitmap()
        end

        # Fills the map which maps the set bits to the
        # count of previously set bits.
        private def fill_bitmap
            val = @value
            biti = 0
            count = 0

            while (val != 0)
                if val & 1 != 0
                    @bit_map[biti] = count
                    count += 1
                end
                biti += 1
                val = val >> 1
            end
        end

        def get_trace_count 
            return Math.max(Isekai.ceillg2(@value), @bus.get_trace_count)
        end

        private def bit_value (i)
            return (@value >> i) & 1
        end

        def do_trace (i)
            if @bit_map[i]?
                count = @bit_map[i]
                k = wires_per_xor()
                return @wire_list.as(WireList)[(count+1)*k - 1]
            else
                return @bus.do_trace(i)
            end
        end

        def get_wire_count
            return wires_per_xor() * @bit_map.size()
        end

        def wires_per_xor
            raise "Abstract."
        end

        def invert_field_op(comment, input_list, output_list)
            raise "Abstract."
        end

        # Generates the needed gates for XOR operation
        def get_field_ops
            cmds = Array(FieldOp).new()

            (0..get_trace_count()-1).each do |i|
                if count = @bit_map[i]?
                    k = wires_per_xor()

                    cmds << invert_field_op(
                        "bitxor bit #{i}",
                        @bus.get_trace(i),
                        @wire_list.as(WireList)[count * k..(count+1)*k]
                    )
                end
            end

            return cmds
        end
    end

    # Bus that checks if all wires are set.
    class AllOnesBase < BooleanBus
        def initialize (@board, @bus : Bus) 
            super(@board, Constants::MAJOR_LOGIC)
        end

        def get_trace_count
            return 1
        end
        
        def get_wire_count
            return @bus.get_trace_count() - 1
        end

        def and_field_op (comment : String, inputs : WireList, outputs : WireList)
            raise "Abstract."
        end

        def get_field_ops
            cmds = Array(FieldOp).new()
            prev_wire = @bus.get_trace(0)

            (1..@bus.get_trace_count()-1).each do |i|
                out_wire = @wire_list.as(WireList)[i-1]
                    cmds << and_field_op(
                        "all ones", 
                        WireList.new([prev_wire, @bus.get_trace(i)]),
                        WireList.new([out_wire])
                    )

                    prev_wire = out_wire
            end

            return cmds
        end

        def do_trace(i)
            return @wire_list.as(WireList)[-1]
        end
    end

    class LeftShiftBus < BooleanBus
        def initialize (@board, @bus : Bus, @left_shift : Int32)
            super(@board,Constants::MAJOR_LOGIC)
        end

        def get_trace_count()
            return @board.bit_width.truncate(Math.max(0, @bus.get_trace_count() + @left_shift))
        end

        def get_wire_count()
            return 0
        end

        def get_field_ops()
            return Array(FieldOp).new()
        end

        def do_trace (i)
            parent_bit = i - @left_shift
            if parent_bit == 0 || i > get_trace_count()
                return @board.zero_wire
            else
                return @bus.get_trace(parent_bit)
            end
        end
    end

    abstract class BinaryBooleanBus < BooleanBus
        def initialize (@board, @bus_left : Bus, @bus_right : Bus)
            super(@board, Constants::MAJOR_LOGIC)
            raise "Can't combine non-boolean buses" if @bus_left.get_trace_type != Constants::BOOLEAN_TRACE
            raise "Can't combine non-boolean buses" if @bus_right.get_trace_type != Constants::BOOLEAN_TRACE
        end

        def get_trace_count
            return Math.max(@bus_left.get_trace_count, @bus_right.get_trace_count)
        end
    end
end