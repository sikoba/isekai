require "./reqfactory"
require "./bus"
require "./booleanbusreq"
require "../dfg"

module Isekai

# Check ReqFactory's documentation.
class BooleanFactory < RequestFactory
    def initialize(@output_filename : String, @circuit_inputs : Array(DFGExpr),
        @circuit_outputs : Array(Tuple(StorageKey, DFGExpr))?, @bit_width : Int32)
        super(@output_filename, @circuit_inputs, nil, @circuit_outputs, @bit_width, [] of Int32)
    end

    def type : String
        return Constants::BOOLEAN_TRACE
    end

	def make_zero_bus()
        return BooleanZero.new(get_board())
    end

	def make_input_req(expr)
		return BooleanInputReq.new(self, expr.as(InputBase), type())
    end

	def make_output_bus(expr_bus : Bus, idx)
		return BooleanOutputBus.new(get_board(), expr_bus, idx)
    end

    def make_req(expr, type : String) : BaseReq
        case expr
        when .is_a? Input
            result = BooleanInputReq.new(self, expr, type)
        when .is_a?  Constant
                result = ConstantReq.new(self, expr, type)
        when .is_a?  Add
                result = AddReq.new(self, expr, type)
        when .is_a?  Negate
                result = NegateReq.new(self, expr, type)
	    else
             result = super(expr, type)
        end
        return result
    end

    def collapse_req(req)
        return req.natural_impl()
    end

    def get_BitAndBus_class()
        raise "unimplemented"
    end

    def get_BitOrBus_class()
        return BitOrBus
    end

    def get_XorBus_class()
        raise "unimplemented"
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

    def get_ConstantArithmeticBus_class
        raise "Unsupported"
    end

    # Does nothing for boolean, has to be here for the code to compile
	def truncate(expr, bus)
		return bus
    end
end
end