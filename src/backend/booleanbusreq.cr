require "./busreq.cr"
require "./bus.cr"
require "./booleanbus.cr"

module Isekai::Backend
    # Requests to lay down the boolean circuit buses.

    abstract class BooleanReq < BusReq
        def natural_type
            return Constants::BOOLEAN_TRACE
        end
    end

    class BooleanInputReq < BooleanReq
        def initialize (@reqfactory, @expr, @type : String)
            super(@reqfactory, @expr, @type)
        end

        def natural_dependencies
            return Array(BaseReq).new()
        end

        def natural_impl
            return BooleanInputBus.new(board(), @expr.as(Field).@key.@idx)
        end
    end

    abstract class BooleanBinaryOpReq < BinaryOpReq
        def natural_type
            return Constants::BOOLEAN_TRACE
        end

        def has_constant_opt
            return false
        end
    end

    class AddReq < BooleanBinaryOpReq
        def has_constant_opt
            return false
        end

        def var_impl (*buses)
            return BooleanAddBus.new(board(), buses[0], buses[1])
        end
    end
end
