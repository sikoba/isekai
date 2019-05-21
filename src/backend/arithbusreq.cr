require "./bus.cr"
require "./arithbuses.cr"
require "../dfg.cr"
require "./busreq.cr"

module Isekai

# Refer to BusReq's documentation for more explanation.

class ArithmeticInputReq < BusReq
	def initialize(@reqfactory, @expr, @trace_type : String)
    end

	def natural_type()
        return Constants::ARITHMETIC_TRACE
    end

	def natural_dependencies()
        Array(BaseReq).new()
    end

	def natural_impl()
        return ArithmeticInputBus.new(board(), @expr.as(InputBase).@storage_key.@idx)
    end
end

class ArithmeticNIZKInputReq < BusReq
	def initialize(@reqfactory, @expr, @trace_type : String)
        super(@reqfactory, @expr, @trace_type)
    end

    def natural_type()
        return Constants::ARITHMETIC_TRACE
    end

	def natural_dependencies()
        Array(BaseReq).new()
    end

	def natural_impl()
        return ArithmeticNIZKInputBus.new(board(), @expr.as(InputBase).@storage_key.@idx)
    end
end

class ArithAddReq < BinaryOpReq
	def initialize(@reqfactory, @expr, @trace_type : String)
        super(@reqfactory, @expr, @trace_type)
    end

    def natural_type()
       return Constants::ARITHMETIC_TRACE
    end

    def has_constant_opt()
         return false
    end

	def var_impl(*busses)
        return ArithAddBus.new(board(), to_s(), *busses)
    end
end

class ArithMultiplyReq < BinaryOpReq
	def initialize(@reqfactory, @expr, @trace_type : String)
        super(@reqfactory, @expr, @trace_type)
    end

    def natural_type()
       return Constants::ARITHMETIC_TRACE
    end

    def has_constant_opt()
        return true
    end

    # Implementation in case of a multiply by constant.
	def const_impl(const_expr, variable_bus)
        return ConstantMultiplyBus.new(board(), const_expr.as(Constant).@value.to_i64, variable_bus)
    end

    # Lays down full arithmetic multiply bus. 
	def var_impl(*busses)
        return ArithMultiplyBus.new(board, *busses)
    end
end

# Negate bus request.
class NegateReq < BusReq
    def initialize(@reqfactory, @expr, @trace_type)
    end

    def natural_type()
       return Constants::ARITHMETIC_TRACE
    end

	private def req
        return make_req(@expr.as(Negate).@expr, natural_type())
    end

	def natural_dependencies()
        return [ req() ]
    end

	def natural_impl()
		sub_bus = get_bus_from_req(req())
        return ConstantMultiplyBus.new(board(), -1_i64, sub_bus)
    end
end

# Conditional bus - outputs arithmetic value based on the boolean condition.
class ArithConditionalReq < BusReq
	def natural_type()
        return Constants::ARITHMETIC_TRACE
    end

	private def reqcond()
        return LogicalCastReq.new(@reqfactory, @expr.as(Conditional).@cond, Constants::BOOLEAN_TRACE)
    end

	private def reqtrue()
        return @reqfactory.make_req(@expr.as(Conditional).@valtrue, Constants::ARITHMETIC_TRACE)
    end

	private def reqfalse()
        return @reqfactory.make_req(@expr.as(Conditional).@valfalse, Constants::ARITHMETIC_TRACE)
    end

    # Depend on all inputs.
	def natural_dependencies()
        return [ reqcond(), reqtrue(), reqfalse() ]
    end

	def natural_impl()
		buscond : Bus = get_bus_from_req(reqcond())
		bustrue : Bus = get_bus_from_req(reqtrue())
		busfalse : Bus = get_bus_from_req(reqfalse())
		return ArithmeticConditionalBus.new(board(), buscond, bustrue, busfalse)
    end
end

# Generic compare request.
abstract class CmpReq < BinaryOpReq
    def natural_type()
       return Constants::ARITHMETIC_TRACE
    end

    def has_constant_opt()
        return false
    end

    abstract def var_impl(abus, bbus)
end

# Compares less-than in boolean domain and then moves back to arithmetic (using split and join buses)
class CmpLTReq < CmpReq
        def var_impl(abus, bbus)
            if(board().bit_width.get_width() > 32) #TODO we should handle also bigger width, by using BigInt when size > 64
                raise "unsupported width...TODO"
            end
            minusb_bus = ConstantMultiplyBus.new(board(), board().bit_width.get_neg1().to_i64, bbus)
            @reqfactory.add_extra_bus(minusb_bus)

            left_class = typeof(@expr.as(BinaryOp).@left)
            right_class = typeof(@expr.as(BinaryOp).@right)
            comment = "CmpLT #{left_class} - #{right_class}"
            # a - b
            aminusb_bus = ArithAddBus.new(board(), comment, abus, minusb_bus)
            @reqfactory.add_extra_bus(aminusb_bus)
            # split into bits
            split_bus = SplitBus.new(board(), aminusb_bus)
            @reqfactory.add_extra_bus(split_bus)
            # shift left the result in bitwise domain and check the sign bit.
            signbit = LeftShiftBus.new(board(), split_bus, -board().bit_width.get_sign_bit())
            @reqfactory.add_extra_bus(signbit)
            return JoinBus.new(board(), signbit)
        end
end

class CmpLEQReq < CmpLTReq
        # less or equal, same as above, just add 1 to the right operand
        def var_impl(abus, bbus)
                constant_one = ConstantArithmeticBus.new(board(), 1)
                @reqfactory.add_extra_bus(constant_one)
                comment = "CmpLEQ #{typeof(@expr.as(BinaryOp).@right)} + 1"
                bplus1_bus = ArithAddBus.new(board(), comment, bbus, constant_one)
                @reqfactory.add_extra_bus(bplus1_bus)
                return super(abus, bplus1_bus)
        end
end

class CmpEQReqArith < CmpReq
    def initialize(reqfactory, expr, type)
        super(reqfactory, expr, type)
    end

    def var_impl(abus : Bus, bbus : Bus)
            # Check EQuality using ZeroP gate.
            zerop_bus = ArithmeticZeroPBus.new(board(), abus, bbus)
            @reqfactory.add_extra_bus(zerop_bus)
            return zerop_bus
    end
end
end