
module Isekai
    class Wire
        def initialize (@idx : Int32)
        end

        def_hash @idx
        def_equals @idx

        def to_s(io)
            io << "#{@idx}"
        end
    end

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