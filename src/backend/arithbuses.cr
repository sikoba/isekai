require "./bus"
require "./arithmeticfieldops"
require "./helpers"
require "math"

module Isekai::Backend

# Base for the arithmetic bus.
abstract class ArithmeticBus < Bus
	def initialize (@board, @major)
        super(@board, @major)
    end

	def get_trace_type
       return Constants::ARITHMETIC_TRACE
    end

    # Abstract, but has to be implemented to avoid
    # nonsense implementations in concrete cases.
	def get_trace_count() : Int32
        return 1
    end

    def get_active_bits() : Int32
        return 0
    end

    # Gets the value of the last wire. Will be overriden
	def do_trace(j)
        raise "Bus should implement more if wants to access non-last element" unless j == 0
        if wire_list = @wire_list
            return wire_list[-1]
        else
            raise "No wire list yet assigned."
        end
    end
end

# Zero bus - multiplies one-wire with 0 and generates 0 output.
class ArithZero < ArithmeticBus
	def initialize (@board)
        super(@board, Constants::MAJOR_LOGIC)
    end

    # Only one wire needed.
    def get_wire_count()
        return 1
    end

    # Multiply one-bus with 0 and get the zero output.
	def get_field_ops()
		return [ FieldConstMul.new("zero", 0, @board.one_wire(), @wire_list.as(WireList)[0]) ]
    end

	def do_trace(j)
        return @wire_list.as(WireList)[0]
    end
end

# Input bus.
abstract class ArithmeticInputBaseBus < ArithmeticBus
    @used : Bool?
 
	def initialize (@major, @board, @input_idx : Int32)
        super(@board, @major)
        @used = nil
    end

	def set_used(used)
        @used = used
    end

    # Possible maximum number of active bits is bit width
	def get_active_bits()
        return @board.bit_width.get_width()
    end

	def get_wire_count()
        return 1
    end

    #Fix issue with reverse inputs; order is stricly on the input index, and not just on the type
    def <(other : Bus)
        if other.is_a? typeof(self) && orders[0] == other.orders[0]
            return @input_idx < other.as(typeof(self)).@input_idx
        else
            return super(other)
        end
    end

    def <=>(other : Bus)
        # Override <=> because crystal 0.28 is using it for sorting
        other < self  ? 1 : (self < other ? -1 : 0)
    end
end

# Concrete input
class ArithmeticInputBus < ArithmeticInputBaseBus
	def initialize (@board, @input_idx : Int32)
        super(Constants::MAJOR_INPUT, @board, @input_idx)
    end

	def get_field_ops()
		comment = "input"
		if (!@used)
            comment += " (unused)"
        end
        return [ FieldInput.new(comment, Wire.new(@wire_list.as(WireList)[0].@idx)) ]
    end
end

# Concrete NIZK input
class ArithmeticNIZKInputBus < ArithmeticInputBaseBus
	def initialize (@board, @input_idx : Int32)
        super(Constants::MAJOR_INPUT_NIZK, @board, @input_idx)
    end

    def get_field_ops()
		comment = "input"
		if (!@used)
            comment += " (unused)"
        end
        return [ FieldNIZKInput.new(comment, Wire.new(@wire_list.as(WireList)[0].@idx)) ]
    end
end

# Output bus.
class ArithmeticOutputBus < ArithmeticBus
	def initialize (@board, @bus_in : Bus, @output_idx : Int32)
        super(@board, Constants::MAJOR_OUTPUT)
		# caller responsible to put outputs in order expected by C spec
        set_order(@output_idx)
    end

	def get_wire_count()
        return 1
    end

    # Changes the width of the last logic gate into the output.
	def get_field_ops()
		fm = FieldMul.new("output-cast",
				WireList.new([@board.one_wire(), @bus_in.get_trace(0)]),
				WireList.new([@wire_list.as(WireList)[0]]))
		fo = FieldOutput.new("", @wire_list.as(WireList)[0])
        return [ fm, fo ]
    end
end

# Special case ZeroP bus - to implement EQ check without boolean
# gates.
class ArithmeticZeroPBus < ArithmeticBus
    def initialize (@board, @in_bus : Bus, @in_bus_b : Bus)
        super(@board, Constants::MAJOR_LOGIC)
    end

    def get_active_bits()
        return 1
    end

    def get_wire_count()
        return 6
    end

    # Generate EQ operation from primitive gates.
    def get_field_ops()
            negb = FieldConstMul.new("zerop subtract negative", -1, @in_bus_b.get_trace(0), @wire_list.as(WireList)[0])
            diff = FieldAdd.new("zerop diff",
                            WireList.new([@in_bus.get_trace(0), @wire_list.as(WireList)[0]]),
                            WireList.new([@wire_list.as(WireList)[1]]))

            fzp = FieldZeroP.new("zerop %s" % @in_bus,
                                @wire_list.as(WireList)[1],
                                @wire_list.as(WireList)[2], @wire_list.as(WireList)[3])
            inv = FieldConstMul.new("zerop inverse",
                                -1,
                                @wire_list.as(WireList)[2],
                                @wire_list.as(WireList)[4])
            res = FieldAdd.new("zerop result",
                            WireList.new([@board.one_wire(),
                                        @wire_list.as(WireList)[4]]),
                            WireList.new([@wire_list.as(WireList)[5]]))
            return [negb, diff, fzp, inv, res]
    end
end

# Constant value
class ConstantArithmeticBus < ArithmeticBus
	def initialize (@board, @value : Int64)
        super(@board, Constants::MAJOR_LOGIC)
    end

	def get_active_bits()
		return Isekai::Backend.ceillg2(@value)
    end

	def get_wire_count()
        return 1
    end

	def get_field_ops()
        return [ FieldConstMul.new( "constant #{@value}", @value.to_i64, @board.one_wire(), @wire_list.as(WireList)[0]) ]
    end
end

# Multiply by constant
class ConstantMultiplyBus < ArithmeticBus
    @active_bits : Int32

	def initialize (@board, @value : Int64, @bus : Bus)
        super(@board, Constants::MAJOR_LOGIC)
        if (@board.bit_width.get_width()<=32)
            @value = (value & @board.bit_width.get_neg1().to_i64) 
        else
            @value = (BigInt.new(value) & @board.bit_width.get_neg1()).to_i64
        end
        @active_bits = Isekai::Backend.ceillg2(@value) + @bus.get_active_bits()
    end

	def get_active_bits()
        return @active_bits
    end

	def get_wire_count()
        return 1
    end

	def get_field_ops()
		return [ FieldConstMul.new("multiply-by-constant #{@value}", @value, @bus.get_trace(0), @wire_list.as(WireList)[0]) ]
    end
end

# Same as Multiply by constant but without 32 bits handle, to use with caution.
class ConstantNegBus < ArithmeticBus
    @active_bits : Int32

	def initialize (@board, @value : Int64, @bus : Bus)
        super(@board, Constants::MAJOR_LOGIC)
        @active_bits = Isekai::Backend.ceillg2(@value) + @bus.get_active_bits()
    end

	def get_active_bits()
        return @active_bits
    end

	def get_wire_count()
        return 1
    end

	def get_field_ops()
		return [ FieldConstMul.new("multiply-by-constant #{@value}", @value, @bus.get_trace(0), @wire_list.as(WireList)[0]) ]
    end
end

# Conditional bus
class ArithmeticConditionalBus < ArithmeticBus
    @active_bits : Int32

	def initialize (@board, @buscond : Bus, @bustrue : Bus, @busfalse : Bus)
        super(@board, Constants::MAJOR_LOGIC)
		@active_bits = Math.max(@bustrue.get_active_bits(), @busfalse.get_active_bits())
    end

	def get_active_bits()
        return @active_bits
    end

	def get_wire_count()
        return 5
    end

	def get_field_ops()
        # allocates wire needed
        trueterm = @wire_list.as(WireList)[0]
		minuscond = @wire_list.as(WireList)[1]
		negcond = @wire_list.as(WireList)[2]
		falseterm = @wire_list.as(WireList)[3]
        result = @wire_list.as(WireList)[4]
        
        # connects bus true and bus false input (which goes though (-cond-1)*bus_false transformation
        # into the adder and we then get the result based on (cond*bus_true)+bus_false(1-cond)
		return [
			FieldMul.new("cond trueterm",
				WireList.new([@buscond.get_trace(0), @bustrue.get_trace(0)]),
				WireList.new([trueterm])),
			FieldConstMul.new("cond minuscond",
				-1,
				@buscond.get_trace(0),
				minuscond),
			FieldAdd.new("cond negcond",
				WireList.new([@board.one_wire(), minuscond]),
				WireList.new([negcond])),
			FieldMul.new("cond falseterm",
				WireList.new([negcond, @busfalse.get_trace(0)]),
				WireList.new([falseterm])),
			FieldAdd.new("cond result",
				WireList.new([trueterm, falseterm]),
				WireList.new([result]))
			]
    end
end


abstract class BinaryArithmeticBus < ArithmeticBus
	def initialize (@board, @bus_left, @bus_right, @active_bits : Int32)
        super(@board, Constants::MAJOR_LOGIC)
    end

    def get_wire_count()
        return 1
    end

	def get_active_bits()
        return @active_bits
    end
end

# Add bus - lays the adder on the board
class ArithAddBus < BinaryArithmeticBus
	def initialize (@board, @comment : String, @bus_left : Bus, @bus_right : Bus)
        max_bits = Math.max(bus_left.get_active_bits(), bus_right.get_active_bits())
        # maximum bits is the width + carry
		@active_bits = max_bits + 1
        super(@board, @bus_left, @bus_right, @active_bits)
    end

    # lay down the adder
	def get_field_ops()
		return [ FieldAdd.new(
				@comment,
				WireList.new([@bus_left.get_trace(0),
					@bus_right.get_trace(0)]),
                wire_list) ]
    end
end

# Multiply bus - lays down the multiplier
class ArithMultiplyBus < BinaryArithmeticBus
    def initialize (@board, @bus_left : Bus, @bus_right : Bus)
        # maximum active bits is a sum of active bits of operands
		@active_bits = bus_left.get_active_bits() + bus_right.get_active_bits()
        super(@board, @bus_left, @bus_right, @active_bits)
    end

	def get_field_ops()
		return [ FieldMul.new(
				"multiply",
				WireList.new([@bus_left.get_trace(0),
					@bus_right.get_trace(0)]),
                wire_list) ]
    end
end

# Operators for conversion from boolean to arithmetic form
# and vice-versa
class JoinBus < Bus
    @active_bits : Int32

	# Convert a Constants::BOOLEAN_TRACE bus into an Constants::ARITHMETIC_TRACE bus
	def initialize (@board, @input_bus : Bus)
        super(@board, Constants::MAJOR_LOGIC)
		raise "Already arith. bus" if (input_bus.get_trace_type() == Constants::ARITHMETIC_TRACE)
		@input_bus = input_bus
		@active_bits = input_bus.get_trace_count()
    end

    def get_trace_type()
       return Constants::ARITHMETIC_TRACE
    end

	def get_active_bits()
        return @active_bits
    end

	def get_trace_count()
        return 1
    end

	def get_wire_count()
        return 2*(@active_bits-1)
    end

	def get_field_ops()
		in_width = @active_bits
		cmds = Array(FieldOp).new()
		comment = "join"
		(0..in_width-1-1).each do |biti|
			bit = in_width - 1 - biti
			if (biti == 0)
				prevwire = @input_bus.get_trace(bit)
				mulcomment = " source bit %s" % bit
			else
				prevwire = @wire_list.as(WireList)[biti*2 - 1]
                mulcomment = ""
            end

			factor_output = @wire_list.as(WireList)[biti*2]
			cmds << FieldConstMul.new(comment+mulcomment, 2, prevwire, factor_output)

			addcomment = " source bit %s" % (bit-1)
			term_in_list = WireList.new([
				@input_bus.get_trace(bit-1),
				factor_output])
			term_output = WireList.new([@wire_list.as(WireList)[biti*2 + 1]])
            cmds << FieldAdd.new(comment+addcomment, term_in_list, term_output)
        end
		return cmds
    end

	def do_trace(j)
		if (@active_bits==1)
			return @input_bus.get_trace(0)
		else
            return @wire_list.as(WireList)[-1]
        end
    end
end

class SplitBus < Bus
    @trace_count : Int32

	# Convert anConstants::ARITHMETIC_TRACE bus into a Constants::BOOLEAN_TRACE bus
	def initialize (@board, @input_bus : Bus)
        super(@board, Constants::MAJOR_LOGIC)
		@trace_count = @board.bit_width.truncate(@input_bus.get_active_bits())
    end

	def to_s()
        return "SplitBus"
    end

	def get_trace_type()
        return Constants::BOOLEAN_TRACE
    end

	def get_trace_count()
        return @trace_count
    end
	
	def get_wire_count()
		if (@input_bus.get_active_bits()==1)
			return 0
		else
            return @input_bus.get_active_bits()
        end
    end

	def get_field_ops()
		if (@input_bus.get_active_bits()==1)
			return Array(FieldOp).new()
		else
			return [ FieldSplit.new(to_s(),
					WireList.new([@input_bus.get_trace(0)]),
                    wire_list) ]
        end
    end

	def do_trace(j)
		if (@input_bus.get_active_bits()==1)
			return @input_bus.get_trace(0)
		else
            return @wire_list.as(WireList)[j]
        end
    end

    def get_active_bits
        return 0
    end
end


# Boolean operations with arithmetic fieldop implementations
# which are more performant then the native ones.
class ConstantBitXorBus < ConstantBitXorBusBase
	def initialize (@board, @value, @bus)
        super(@board, @value, @bus)
    end

	def wires_per_xor()
        return 2
    end

	def invert_field_op(comment : String, in_wire : Wire, minus_wire : Wire, xor_wire : Wire)
		return [
			FieldConstMul.new(comment, -1, in_wire, minus_wire),
			FieldAdd.new(comment,
				WireList.new([@board.one_wire(), minus_wire]),
				WireList.new([xor_wire]))
            ]
    end
end

class AllOnesBus < AllOnesBase
	def initialize (@board, @bus : Bus)
        super(@board, @bus)
    end

	def and_field_op(comment : String, inputs : WireList, outputs : WireList)
        return FieldMul.new(comment, inputs, outputs)
    end
end

class ArithBitAndBus < BinaryBooleanBus
	def initialize (@board, @bus_left, @bus_right)
        super(@board, @bus_left, @bus_right)
    end

	def get_wire_count()
        return get_trace_count()
    end

	def do_trace(j)
        return @wire_list.as(WireList)[j]
    end

	def get_field_ops()
		cmds = Array(FieldOp).new()
		(0..get_trace_count()-1).each do |out_bit|
			comment = "bitand bit #{out_bit}"
			cmds << FieldMul.new(comment,
				WireList.new([@bus_left.get_trace(out_bit), @bus_right.get_trace(out_bit)]),
                WireList.new([@wire_list.as(WireList)[out_bit]]))
        end
        return cmds
    end
end

# Support for == using the zero-equal field operation
class EqlBusArith < ArithmeticBus
    def initialize (@board, @bus_left : Bus, @bus_right : Bus)
        super(@board, Constants::MAJOR_LOGIC)
        @trace_count = 1
    end

    def get_trace_count()
        return @trace_count
    end

    def get_wire_count()
        return 3
    end

    def get_trace_type()
        return Constants::BOOLEAN_TRACE
    end

    def get_field_ops()
        cmds = Array(FieldOp).new()
        comment = "Eql "
        rightneg = @wire_list.as(WireList)[0]
        cmds << FieldConstMul.new(comment+"-1 * right", -1, @bus_right.do_trace(0), rightneg)
        leftplusright = @wire_list.as(WireList)[1]
        cmds << FieldAdd.new(comment + "left + (-1 * right)",
                                WireList.new([@bus_left.get_trace(0), rightneg]),
                                WireList.new([leftplusright]))

        result = @wire_list.as(WireList)[2]
        cmds << FieldZeroP.new(comment + "zerop(left + (-1 * right))",
                                leftplusright,
                                result, nil)
        return cmds
    end
end

# Equality using boolean ops.
class EqlBusBoolean < BooleanBus
        def initialize (@board, @bus_left : Bus, @bus_right : Bus)
            super(@board, Constants::MAJOR_LOGIC)
            @trace_count = 1
        end

        private def make_xnor(board, left_bus, right_bus, j, wire_list)
            cmds = Array(FieldOp).new()
            comment = "XNOR bit #{j}"
            aplusb = wire_list[0]
            cmds << FieldAdd.new(comment+"a+b", WireList.new([left_bus.get_trace(j),
                                                            right_bus.get_trace(j)]),
                                    WireList.new([aplusb]))
            ab = wire_list[1]
            cmds << FieldMul.new(comment+"ab",
                                    WireList.new([left_bus.get_trace(j),
                                            right_bus.get_trace(j)]),
                                    WireList.new([ab]))
            minus2ab = wire_list[2]
            cmds << FieldConstMul.new(comment+"-2ab",
                                        -2, ab, minus2ab)
            xor = wire_list[3]
            cmds << FieldAdd.new(comment+"(a+b)-2ab",
                                    WireList.new([aplusb, minus2ab]),
                                    WireList.new([xor]))
            neg = wire_list[4]
            cmds << FieldConstMul.new(comment+"-1 * ((a + b) - 2ab)",
                                        -1, xor, neg)
            result = wire_list[5]
            cmds << FieldAdd.new(comment+"1 - ((a+b) - 2ab)",
                                    WireList.new([board.one_wire(), neg]),
                        WireList.new([result]))
            return cmds
        end

        def get_trace_count()
            return @trace_count
        end

        def get_wire_count()
            return @bus_left.get_trace_count()*7-1
        end

        def get_field_ops() 
            cmds = Array(FieldOp).new()
            (0..@bus_left.get_trace_count()-1).each do |i|
                    # Xor the left with the right, then compute AND tree
                    cmds.concat(make_xnor(@board, @bus_left, @bus_right, i, @wire_list.as(WireList)[6*i..6*(i+1)]))
            end

            cmds << FieldMul.new("AND tree for EqlBus bit 0-1", 
                                    WireList.new([@wire_list.as(WireList)[5], @wire_list.as(WireList)[11]]),
                                    WireList.new([@wire_list.as(WireList)[6*@bus_left.get_trace_count()]]))

            (0..@bus_left.get_trace_count()-2-1).each do |i|
                    # AND tree
                    cmds << FieldMul.new("AND tree for EqlBus bit #{i+2}",
                                            WireList.new([@wire_list.as(WireList)[6*(i+3)-1],
                                                    @wire_list.as(WireList)[6*@bus_left.get_trace_count() + i]]),
                                            WireList.new([@wire_list.as(WireList)[6*@bus_left.get_trace_count() + i + 1]]))
            end

            return cmds
        end

        def do_trace(j)
            return @wire_list.as(WireList)[7*@bus_left.get_trace_count()-2]
        end
end

# Defines Or or Xor boolean operations using arithmetic ops.
class OrFamilyBus < BinaryBooleanBus
	def initialize (@board, @bus_left, @bus_right, @product_coeff : Int32, @c_name : String)
        super(@board, @bus_left, @bus_right)
    end

	def get_wire_count()
        return 4*get_trace_count()
    end

	def get_field_ops()
		cmds = Array(FieldOp).new()
        (0..get_trace_count()-1).each do |i|
			comment = "#{@c_name} bit @{i} "
			# (a+b)-k(ab)
			aplusb = @wire_list.as(WireList)[i*4]
			cmds << FieldAdd.new(comment+"a+b",
				WireList.new([@bus_left.get_trace(i),
					@bus_right.get_trace(i)]),
				WireList.new([aplusb]))
			ab = @wire_list.as(WireList)[i*4+1]
			cmds << FieldMul.new(comment+"ab",
				WireList.new([@bus_left.get_trace(i),
					@bus_right.get_trace(i)]),
				WireList.new([ab]))
			minus2ab = @wire_list.as(WireList)[i*4+2]
			cmds << FieldConstMul.new(comment+"#{@product_coeff}ab",
				@product_coeff.to_i64, ab, minus2ab)
			result = @wire_list.as(WireList)[i*4+3]
			cmds << FieldAdd.new(comment+"(a+b)#{@product_coeff}ab",
				WireList.new([aplusb, minus2ab]),
                WireList.new([result]))
        end
        return cmds
    end

	def do_trace(j)
        return @wire_list.as(WireList)[j*4+3]
    end
end

class ArithBitOrBus < OrFamilyBus
	def initialize (@board, bus_left, bus_right)
        super(@board, bus_left, bus_right, -1, "or")
    end
end

class ArithXorBus < OrFamilyBus
    def initialize (@board, bus_left, bus_right)
        super(@board, bus_left, bus_right, -2, "xor")
    end
end
			
end
