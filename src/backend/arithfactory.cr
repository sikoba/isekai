require "./reqfactory"
require "./bus"
require "./arithbusreq"
require "../dfg"

module Isekai

# Check ReqFactory's documentation.
class ArithFactory < RequestFactory
    def initialize(@output_filename : String, @circuit_inputs : Array(DFGExpr), @circuit_nizk_inputs : Array(DFGExpr)|Nil,
        @circuit_outputs : Array(Tuple(StorageKey, DFGExpr))?, @bit_width : Int32, @circuit_inputs_val : Array(Int32))
        super(@output_filename, @circuit_inputs, @circuit_nizk_inputs, @circuit_outputs, @bit_width, @circuit_inputs_val)
    end

	def type : String
        return Constants::ARITHMETIC_TRACE
    end

	def make_zero_bus()
        return ArithZero.new(get_board())
    end

	def make_input_req(expr)
		return ArithmeticInputReq.new(self, expr, type())
    end

	def make_nizk_input_req(expr)
		return ArithmeticNIZKInputReq.new(self, expr, type())
    end

	def make_output_bus(expr_bus : Bus, idx)
		return ArithmeticOutputBus.new(get_board(), expr_bus, idx)
    end

    private def get_input_storage!
        return nil if @circuit_inputs.empty?
        return @circuit_inputs[0].as(Field).@key.@storage
    end

    private def get_nizk_input_storage!
        arr = @circuit_nizk_inputs || [] of DFGExpr
        return nil if arr.empty?
        return arr[0].as(Field).@key.@storage
    end

    def make_req(expr, type : String) : BaseReq
        case expr
        when .is_a? Field
            case expr.@key.@storage
            when get_input_storage!
                result = ArithmeticInputReq.new(self, expr.as(Field), type)
            when get_nizk_input_storage!
                result = ArithmeticNIZKInputReq.new(self, expr.as(Field), type)
            else
                raise "Unsupported storage"
            end
		when .is_a? Conditional
			result = ArithConditionalReq.new(self, expr.as(Conditional), type)
		when .is_a? CmpLT
			result = CmpLTReq.new(self, expr.as(CmpLT), type)
		when .is_a? CmpLEQ
			result = CmpLEQReq.new(self, expr.as(CmpLEQ), type)
        when .is_a? CmpEQ
            result = CmpEQReqArith.new(self, expr.as(CmpEQ), type)
		when .is_a? Constant
			result = ConstantReq.new(self, expr.as(Constant), type)
		when .is_a? Add
			result = ArithAddReq.new(self, expr.as(Add), type)
		when .is_a? Subtract
			# NB trying something new here. expr factory does memoization
			# against existing graph, so rolling up a late expr ensures
			# we'll avoid generating a duplicate Negate.
			neg_expr = Negate.new(expr.as(Subtract).@right)
			add_expr = Add.new(expr.as(Subtract).@left, neg_expr)
			result = ArithAddReq.new(self, add_expr, type)
		when .is_a? Multiply
			result = ArithMultiplyReq.new(self, expr.as(Multiply), type)
		when .is_a? Negate
			result = NegateReq.new(self, expr.as(Negate), type)
		else
            result = super(expr, type)
        end
        return result
    end

    # If the type of the buses, doesn't match, use SplitBus/JoinBus
    # to convert.
	def collapse_req(req)
		if (req.natural_type() == req.@trace_type)
			return req.natural_impl()
		else
			bus = req.get_bus_from_req(req.to_natural_type())
            case req.@trace_type
            when Constants::BOOLEAN_TRACE
                return SplitBus.new(req.board(), bus)
            when Constants::ARITHMETIC_TRACE
				return JoinBus.new(req.board(), bus)
            end
            raise "Type must be either arithmetic or boolean"
        end
    end

    # Get all arithmetic buses for the base factory.
    def get_BitAndBus_class()
        return ArithBitAndBus
    end

    def get_BitOrBus_class()
        return ArithBitOrBus
    end

    def get_XorBus_class()
        return ArithXorBus
    end

    def get_ConstantArithmeticBus_class()
        return ConstantArithmeticBus
    end

    def get_ConstantBitXorBus_class()
        return ConstantBitXorBus
    end

    def get_AllOnesBus_class()
        return AllOnesBus
    end

    def get_EqlBus_class()
        return EqlBusArith
    end

    # Truncate buses - split the value into bitwise, truncate
    # and join again.
	def truncate(expr, bus)
		if @truncated_buses.includes? expr
            return @truncated_buses[expr]
        end
		add_extra_bus(bus)
		truncated_bool_bus = SplitBus.new(get_board(), bus)
		add_extra_bus(truncated_bool_bus)
		truncated_bus = JoinBus.new(get_board(), truncated_bool_bus)
		@truncated_buses[expr] = truncated_bus
        return truncated_bus
    end
end
end
