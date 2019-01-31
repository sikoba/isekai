require "./bus.cr"
require "./wire.cr"
require "../bitwidth"

module Isekai
    class Board
        @zero_bus : Bus?
        @order_alloc = 0
        @bit_width : BitWidth?

        def initialize (bit_width : Int32)
            @max_width = 252
            @one_bus = OneBus.new(self)
            @bit_width = BitWidth.new(bit_width, false)
            @order_alloc = 0
        end

        def bit_width : BitWidth
            if wid = @bit_width
                return wid
            else
                raise "Width was not set."
            end
        end

        def one_wire
            return @one_bus.as(OneBus).get_one_wire
        end

        def set_zero_bus(zero_bus)
            @zero_bus = zero_bus
        end

        def get_one_bus()
            @one_bus
        end

        private def get_zero_bus
            if bus = @zero_bus
                return bus
            else
                raise "No zero bus set."
            end
        end

        def zero_wire
            return get_zero_bus().@wire_list.as(WireList)[0]
        end

        def assign_order
            @order_alloc += 1
            return @order_alloc
        end
    end
end