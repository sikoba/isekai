require "./bus.cr"
require "../dfg.cr"

module Isekai
    # Request to lay down the buses. Used to transform the intermediate representation
    # into the bus. It implements Collapser's element's interface (get_dependencies)
    # so it can be used with Collapser to recursively resolve all dependencies and convert
    # it into the single bus.
    abstract class BaseReq
        def initialize (@reqfactory : RequestFactory, @expr : DFGExpr, @trace_type : String)
        end

        def_hash @expr, @trace_type
        def_equals @expr, @trace_type

        # Makes a new request from factory for the given DFGExpr.
        def make_req (expr, trace_type) : BaseReq
            return @reqfactory.make_req(expr, trace_type)
        end

        # Gets the final bus (when resolved by Collapser)
        def get_bus_from_req (req) : Bus
            return @reqfactory.collapser.lookup(req)
        end

        def get_bus (expr, trace_type)
            return get_bus_from_req(make_req(expr, trace_type))
        end

        def board
            return @reqfactory.@board
        end

        # Used in collapser. Every bus has different dependencies.
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

        # If the natural type for this bus is different from the
        # asked type, convert it to a natural type first (ask factory
        # to give the correct bus)
        def get_dependencies() : Array(BaseReq)
            if (natural_type() != @trace_type)
                return [to_natural_type().as(BaseReq)]
            else
                return natural_dependencies()
            end
        end

        # Collapser's interface - just use collapse_req from the factory.
        def collapse_impl
            return @reqfactory.collapse_req(self).as(Bus)
        end
    end

    # Binary operation request. Checks if the constant optimization can be done.
    abstract class BinaryOpReq < BusReq
        @const_expr : DFGExpr?
        @variable_expr : DFGExpr?

        def initialize (@reqfactory : RequestFactory, @expr : BinaryOp, @trace_type)
            super(@reqfactory, @expr, @trace_type)

            # Fold if there's a constant optimization when one of the operands is const.
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

        # Tells if there's a const. optimization. For example, multiply by
        # const can use ConstMulFieldOp which is more performant then multiplier
        # which multiplies two buses. 
        abstract def has_constant_opt

        # Somewhat abstract method
        def const_impl (const_expr : DFGExpr, var_bus : Bus)
            if has_constant_opt == false
                raise "Not implemented for this operation"
            end
        end

        # non-constant implementation - always abstract.
        abstract def var_impl (*buses)

        # Make non-constant request.
        private def variable_req
            return make_req(@variable_expr, natural_type())
        end

        # Dependecies are either just a variable operand, when other is const,
        # or both.
        def natural_dependencies()
            if (@is_const_opn)
                return [variable_req()]
            else
                return [make_req(@expr.as(BinaryOp).@left, natural_type), make_req(@expr.as(BinaryOp).@right, natural_type)]
            end
        end

        # Implementation reused in natural_impl - will either truncate or just lay down
        # buses as is.
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

    # Family of N-buses.
    abstract class NotFamily < BusReq
        # bitwise not - XOR(bus, 1111...11111)
        def make_bitnot (bus)
           return @reqfactory.get_ConstantBitXorBus_class.new(board(), board().bit_width.get_neg1().to_i32, bus)    #TODO to check it is correect for all width!
        end

        # Makes logical not - uses BitXorBus with -1 (all ones)
        # and checks if all ones are set.
        def make_logical_not(bus)
            bitnot = make_bitnot(bus)
            @reqfactory.add_extra_bus(bitnot)
            return @reqfactory.get_AllOnesBus_class.new(board(), bitnot)
        end

        # Casts arith. to boolean.
        def make_logical_cast(bus)
            logical_not = make_logical_not(bus)
            @reqfactory.add_extra_bus(logical_not)
            return make_bitnot(logical_not)
        end

        def natural_type 
            return Constants::BOOLEAN_TRACE
        end
        #NOT needs to be applied on any UnaryOp
        def natural_dependencies
            return [make_req(@expr.as(UnaryOp).@expr, Constants::BOOLEAN_TRACE)]
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

    # Casts a value to one bit boolean value
    class LogicalCastReq < NotFamily
        def natural_impl
            wide_bus = get_bus_from_req(make_req(@expr, Constants::BOOLEAN_TRACE))
            return make_logical_cast(wide_bus)
        end
        #The natural dependency for it is just the expression itself because it doesn’t depend on anything else:
        def natural_dependencies
            return [make_req(@expr, Constants::BOOLEAN_TRACE)]
        end
    end
   

    # Lays down shift request. Right operand must be constant.
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

        # Only left operand is variable.
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