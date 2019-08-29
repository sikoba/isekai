require "./board"

module Isekai::AltBackend::Boolean

struct RequestFactory
    struct Bit
        @[AlwaysInline]
        def initialize (@a : Bool, @x : Wire, @b : Bool)
        end

        @[AlwaysInline]
        def self.new_for_const (c : Bool)
            self.new(a: false, x: Wire.new_invalid, b: c)
        end

        @[AlwaysInline]
        def self.new_for_wire (w : Wire)
            self.new(a: true, x: w, b: false)
        end

        @[AlwaysInline]
        def constant? : Bool
            @a == false
        end

        @[AlwaysInline]
        def as_constant : Int32?
            (@b ? 1 : 0) if constant?
        end

        @[AlwaysInline]
        def negated? : Bool
            @b
        end

        @[AlwaysInline]
        def negation : Bit
            Bit.new(a: @a, x: @x, b: @b ^ true)
        end
    end

    @board : Board

    def initialize (@board)
    end

    private def bit_to_wire! (j : Bit) : Wire
        if j.constant?
            return @board.constant(j.@b)
        elsif j.@b
            return @board.xor(j.@x, @board.one_constant)
        else
            return j.@x
        end
    end

    def input_bits (idx : Int32) : Array(Bit)
        return @board.input(idx).map { |w| Bit.new_for_wire(w) }
    end

    def nizk_input_bits (idx : Int32) : Array(Bit)
        return @board.nizk_input(idx).map { |w| Bit.new_for_wire(w) }
    end

    def bit_xor (j : Bit, k : Bit) : Bit
        if j.constant? || k.constant?
            return Bit.new(
                a: j.@a ^ k.@a,
                x: (j.constant?) ? k.@x : j.@x,
                b: j.@b ^ k.@b)
        end

        if j.@x == k.@x
            return Bit.new_for_const(j.@b ^ k.@b)
        end

        return Bit.new(
            a: true,
            x: @board.xor(j.@x, k.@x),
            b: j.@b ^ k.@b)
    end

    def bit_and (j : Bit, k : Bit) : Bit
        if j.constant?
            return j.@b ? k : j
        end
        if k.constant?
            return k.@b ? j : k
        end
        if j.@x == k.@x
            # Modulo 2, x^2 = x, so:
            # (x + A)(x + B) = x^2 + Ax + Bx + AB = (A+B+1)x + AB
            return Bit.new(
                a: j.@b ^ k.@b ^ true,
                x: j.@x,
                b: j.@b && k.@b)
        end

        if j.@b && k.@b
            # NOR
            return Bit.new(
                a: true,
                x: @board.or(j.@x, k.@x),
                b: true)
        end

        return Bit.new(
            a: true,
            x: @board.and(bit_to_wire!(j), bit_to_wire!(k)),
            b: false)
    end

    def bit_or (j : Bit, k : Bit) : Bit
        if j.constant?
            return j.@b ? j : k
        end
        if k.constant?
            return k.@b ? k : j
        end
        if j.@x == k.@x
            if j.@b == k.@b
                # X OR X
                return j
            else
                # X OR (NOT X)
                return Bit.new_for_const(true)
            end
        end

        if j.@b && k.@b
            # NAND
            return Bit.new(
                a: true,
                x: @board.nand(j.@x, k.@x),
                b: false)
        end

        return Bit.new(
            a: true,
            x: @board.or(bit_to_wire!(j), bit_to_wire!(k)),
            b: false)
    end

    def bit_add_output! (j : Bit) : Nil
        @board.add_output!(bit_to_wire!(j))
    end
end

end
