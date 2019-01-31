require "./bus.cr"
require "./arithbuses.cr"
require "../dfg.cr"
require "./busreq.cr"

module Isekai

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

	def const_impl(const_expr, variable_bus)
        return ConstantMultiplyBus.new(board(), const_expr.as(Constant).@value, variable_bus)
    end

	def var_impl(*busses)
        return ArithMultiplyBus.new(board, *busses)
    end
end

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
        return ConstantMultiplyBus.new(board(), -1, sub_bus)
    end
end

##############################################################################
# ConditionalReq operator.
# accepts a boolean condition and two arithmetic inputs;
# emits an arithmetic output.
##############################################################################

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

abstract class CmpReq < BinaryOpReq
    def natural_type()
       return Constants::ARITHMETIC_TRACE
    end

    def has_constant_opt()
        return false
    end

    abstract def var_impl(abus, bbus)
end

class CmpLTReq < CmpReq
        def var_impl(abus, bbus)
            minusb_bus = ConstantMultiplyBus.new(board(), board().bit_width.get_neg1(), bbus)
            @reqfactory.add_extra_bus(minusb_bus)

            left_class = typeof(@expr.as(BinaryOp).@left)
            right_class = typeof(@expr.as(BinaryOp).@right)
            comment = "CmpLT #{left_class} - #{right_class}"
            aminusb_bus = ArithAddBus.new(board(), comment, abus, minusb_bus)
            @reqfactory.add_extra_bus(aminusb_bus)
            split_bus = SplitBus.new(board(), aminusb_bus)
            @reqfactory.add_extra_bus(split_bus)
            signbit = LeftShiftBus.new(board(), split_bus, -board().bit_width.get_sign_bit())
            @reqfactory.add_extra_bus(signbit)
            return JoinBus.new(board(), signbit)
        end
end

class CmpLEQReq < CmpLTReq
        def var_impl(abus, bbus)
                constant_one = ConstantArithmeticBus.new(board(), 1)
                @reqfactory.add_extra_bus(constant_one)
                comment = "CmpLEQ #{typeof(@expr.as(BinaryOp).@right)} + 1"
                bplus1_bus = ArithAddBus.new(board(), comment, bbus, constant_one)
                @reqfactory.add_extra_bus(bplus1_bus)
                return super(abus, bplus1_bus)
        end
end

abstract class CmpEQReq < CmpReq
        def initialize(reqfactory, expr, type)
            super(reqfactory, expr, type)
        end
end

class CmpEQReqArith < CmpEQReq
        def var_impl(abus : Bus, bbus : Bus)
                # Perform equality test by subtracting and use the zerop gate
                zerop_bus = ArithmeticZeroPBus.new(board(), abus, bbus)
                @reqfactory.add_extra_bus(zerop_bus)

                return zerop_bus
        end
end
end