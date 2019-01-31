
module Isekai
    # A single wire. The wire is connecting two
    # gates and its state is represented by the index.
    # For example, if we have two gates, and one has the output
    # wire with the index 4, and the other one has the input wire
    # with the index 4, these gates are connected
    class Wire
        def initialize (@idx : Int32)
        end

        def_hash @idx
        def_equals @idx

        # String representation - index
        def to_s(io)
            io << "#{@idx}"
        end
    end

    # WireList - groups the list of the wires that
    # logicaly belong together.
    class WireList
        def initialize (@wires : Array(Wire))
        end

        def initialize
            @wires = Array(Wire).new()
        end


        def [](index)
            return @wires[index]
        end

        def size()
            return @wires.size()
        end

        def to_s(io)
            if @wires.size() == 0
                io << "0 <>"
                return
            end
            io << "#{size()} <"
            @wires[0..-2].each do |wire|
                io << wire << " "
            end
            io << @wires[-1] << ">"
        end
    end
end