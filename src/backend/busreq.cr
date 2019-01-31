require "./bus.cr"
require "../dfg.cr"

module Isekai
    abstract class BaseReq
        def initialize (@reqfactory : RequestFactory, @expr : DFGExpr, @trace_type : String)
        end

        def_hash @expr, @trace_type
        def_equals @expr, @trace_type

        def make_req (expr, trace_type) : BaseReq
            return @reqfactory.make_req(expr, trace_type)
        end

        def get_bus_from_req (req) : Bus
            return @reqfactory.collapser.lookup(req)
        end

        def get_bus (expr, trace_type)
            return get_bus_from_req(make_req(expr, trace_type))
        end

        def board
            return @reqfactory.@board
        end

        abstract def get_dependencies() : Array(BaseReq)
    end

    abstract class BusReq < BaseReq
        def initialize (@reqfactory : RequestFactory, @expr : DFGExpr, @trace_type)
        end

        abstract def natural_type
        abstract def natural_dependencies
        abstract def natural_impl

        def to_natural_type
            return self.class.new(@reqfactory, @expr, natural_type)
        end

        def get_dependencies() : Array(BaseReq)
            if (natural_type() != @trace_type)
                return [to_natural_type().as(BaseReq)]
            else
                return natural_dependencies()
            end
        end

        def collapse_impl
            return @reqfactory.collapse_req(self).as(Bus)
        end
    end

    abstract class BinaryOpReq < BusReq
        @const_expr : DFGExpr?
        @variable_expr : DFGExpr?

        def initialize (@reqfactory : RequestFactory, @expr : BinaryOp, @trace_type)
            super(@reqfactory, @expr, @trace_type)

            if (has_constant_opt() && expr.@left.is_a? Constant)
                @is_const_opn = true
                @const_expr = expr.@left
                @variable_expr = expr.@right
            elsif (has_constant_opt() && expr.@right.is_a? Constant)
                @is_const_opn = true
                @const_expr = expr.@right
                @variable_expr = expr.@left
            else
                @is_const_opn = false
                @const_expr = nil
                @variable_expr = nil
            end
        end

        abstract def has_constant_opt
        def const_impl (const_expr : DFGExpr, var_bus : Bus)
            if has_constant_opt == false
                raise "Not implemented for this operation"
            end
        end

        abstract def var_impl (*buses)

        private def variable_req
            return make_req(@variable_expr, natural_type())
        end

        def natural_dependencies()
            if (@is_const_opn)
                return [variable_req()]
            else
                return [make_req(@expr.as(BinaryOp).@left, natural_type), make_req(@expr.as(BinaryOp).@right, natural_type)]
            end
        end

        protected def core_impl (transform_f)
            if @is_const_opn
                if const_expr = @const_expr
                    var_bus = get_bus_from_req(variable_req())
                    return const_impl(const_expr.as(DFGExpr), transform_f.call(var_bus).as(Bus))
                else
                    raise "Has no constant expresion set."
                end
            else
                buses = [
                    transform_f.call(get_bus(@expr.as(BinaryOp).@left, natural_type())),
                    transform_f.call(get_bus(@expr.as(BinaryOp).@right, natural_type()))
                ]

                buses.each do |bus|
                    @reqfactory.add_extra_bus(bus)
                end

                return var_impl(buses[0], buses[1])
            end
        end

        def natural_impl
            identity_transf = ->(bus : Bus) { return bus }
            truncate_transf = ->(bus : Bus) { return @reqfactory.truncate(@expr, bus) }
            if bus = core_impl(identity_transf)

                overflow_limit = board().bit_width.@overflow_limit

                if overflow_limit && bus.get_active_bits() > overflow_limit
                    bus = core_impl(truncate_transf)
                end

                return bus
            else
                raise "Could not reduce BinaryReq to buses"
            end
        end
    end


    abstract class NotFamily < BusReq
        def make_bitnot (bus)
            return @reqfactory.get_ConstantBitXorBus_class.new(board(), board().bit_width.get_neg1(), bus)
        end

        def make_logical_not(bus)
            bitnot = make_bitnot(bus)
            @reqfactory.add_extra_bus(bitnot)
            return @reqfactory.get_AllOnesBus_class.new(board(), bitnot)
        end

        def make_logical_cast(bus)
            logical_not = make_logical_not(bus)
            @reqfactory.add_extra_bus(logical_not)
            return make_bitnot(logical_not)
        end

        def natural_type 
            return Constants::BOOLEAN_TRACE
        end

        def natural_dependencies
            return [make_req(@expr.as(Negate).@expr, Constants::BOOLEAN_TRACE)]
        end

    end

    class BitNotReq < NotFamily
        def natural_impl
            return make_bitnot(get_bus_from_req(make_req(@expr, Constants::BOOLEAN_TRACE)))
        end
    end

    class LogicalNotReq < NotFamily
        def natural_impl
            return make_logical_not(get_bus_from_req(make_req(@expr, Constants::BOOLEAN_TRACE)))
        end
    end

    # Casts multi-trace value to a one bit boolean value
    class LogicalCastReq < NotFamily
        def natural_impl
            wide_bus = get_bus_from_req(make_req(@expr, Constants::BOOLEAN_TRACE))
            return make_logical_cast(wide_bus)
        end
    end

    abstract class ShiftRequest < BusReq
        def natural_type
            return Constants::BOOLEAN_TRACE
        end

        private def req()
            return make_req(@expr.as(BinaryOp).@left, Constants::BOOLEAN_TRACE)
        end

        def natural_impl
            return LeftShiftBus.new(
                board(),
                get_bus_from_req(req()),
                direction() * @expr.as(BinaryOp).@right.as(Constant).@value
            )
        end

        def natural_dependencies
            return [req()]
        end

        abstract def direction()
    end

    class LeftShiftReq < ShiftRequest
        def direction()
            return 1
        end
    end

    class RightShiftReq < ShiftRequest
        def direction()
            return -1
        end
    end

    abstract class BooleanBinaryReq < BinaryOpReq
        def initialize (@reqfactory, @expr, @type : String)
            super(@reqfactory, @expr, @type)
        end

        def natural_type
            return Constants::BOOLEAN_TRACE
        end

        def has_constant_opt
            return false
        end

        def const_impl (const_expr : Constant, variable_bus)
            raise "Unsupported."
        end
    end


    class BitAndReq < BooleanBinaryReq
        def initialize(@reqfactory, @expr, @type : String)
            super(@reqfactory, @expr, @type)
        end

        def has_constant_opt
            return true
        end

        def const_impl(const_expr : Constant, variable_bus)
            return ConstBitAndBus.new(board(), const_expr.@value, variable_bus)
        end

        def var_impl (*busses)
            return @reqfactory.get_BitAndBus_class().new(board(), *busses)
        end
    end
    
    class BitOrReq < BooleanBinaryReq
        def initialize(@reqfactory, @expr, @type : String)
            super(@reqfactory, @expr, @type)
        end

        def has_constant_opt
            return true
        end
    
        def const_impl(const_expr : Constant, variable_bus)
            return ConstBitOrBus.new(board(), const_expr.@value, variable_bus)
        end

        def var_impl (*busses)
            return @reqfactory.get_BitAndBus_class().new(board(), *busses)
        end
    end
    
    class XorReq < BooleanBinaryReq
        def initialize(@reqfactory, @expr, @type : String)
            super(@reqfactory, @expr, @type)
        end
    
        def has_constant_opt
            return true
        end

        def const_impl(const_expr : Constant, variable_bus)
            return @reqfactory.get_ConstantBitXorBus_class().new(
                board(), const_expr.@value, variable_bus)
        end

        def var_impl (*busses)
            return @reqfactory.get_BitAndBus_class().new(board(), *busses)
        end
    end

    class ConstantReq < BaseReq
        def get_dependencies
            return Array(BaseReq).new
        end

        def collapse_impl
            if @trace_type == Constants::BOOLEAN_TRACE
                return ConstantBooleanBus.new(board(), @expr.as(Constant).@value).as(Bus)
            else
                return @reqfactory.get_ConstantArithmeticBus_class.new(board(), @expr.as(Constant).@value).as(Bus)
            end
        end
    end
end