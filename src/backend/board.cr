require "./bus.cr"
require "./wire.cr"
require "big"

module Isekai::Backend
    # Board bit width class - holds the bit width of the board,
    # and provides convenience methods to calculate sign bit's value,
    # -1 constant, shifts and truncate.
    class BoardBitWidth
        @overflow_limit : Int32?

        def initialize(width : Int32, ignore_overflow)
            @width = width
            if (!ignore_overflow)
                @overflow_limit = 250
            end
        end

        def ignoring_overflow()
            return @overflow_limit.is_a? Nil
        end

        def get_width()
            return @width
        end

        def get_sign_bit()
            return @width - 1
        end

        def get_neg1()
           # return (1 << @width) - 1
           return ((BigInt.new(1) << @width) -1) 
        end

        def leftshift(a, b)
            return (a<<b) & get_neg1()
        end

        def rightshift(a, b)
            return ((a & get_neg1()) >> b)
        end

        def truncate(bits)
            if (@overflow_limit && bits >= get_width())
                return get_width()
            else
                return bits
            end
        end
    end

    # Board class. Defines the bit width, zero bus and constant-1 bus.
    class Board
        @zero_bus : Bus?
        @order_alloc = 0
        @bit_width : BoardBitWidth?

        def initialize (bit_width : Int32)
            @max_width = 252
            @one_bus = OneBus.new(self)
            @bit_width = BoardBitWidth.new(bit_width, false)
            @order_alloc = 0
        end

        # Gets the bit width of the system
        def bit_width
            if wid = @bit_width
                return wid
            else
                raise "Width was not set."
            end
        end

        # Gets the constant-one wire
        def one_wire
            return @one_bus.as(OneBus).get_one_wire
        end

        # Sets the zero bus (the value of this bus is always 0)
        def set_zero_bus(zero_bus)
            @zero_bus = zero_bus
        end

        def get_one_bus()
            @one_bus
        end

        def get_zero_bus
            if bus = @zero_bus
                return bus
            else
                raise "No zero bus set."
            end
        end

        # Gets the zero-value wire
        def zero_wire
            return get_zero_bus().@wire_list.as(WireList)[0]
        end

        # Returns the order of the new bus. Orders are ever-increasing
        # and every bus gets a different order.
        def assign_order
            @order_alloc += 1
            return @order_alloc
        end
    end
end
