require "../collapser.cr"
require "./board.cr"
require "../dfg.cr"
require "./busreq.cr"
require "./bus.cr"

module Isekai
    abstract class RequestFactory < Collapser(BaseReq, Bus)
        def initialize(@output_filename : String, @circuit_inputs : Array(DFGExpr), @circuit_nizk_inputs : Array(DFGExpr)|Nil,
                @circuit_outputs : Array(Tuple(StorageKey, DFGExpr)), @bit_width)
            super()
            @board = Board.new(@bit_width)
            @buses = Set(Bus).new
            @truncated_buses = Hash(DFGExpr, Bus).new
            @total_wire_count = 0
            @bus_list = Array(Bus).new()

            add_extra_bus(@board.get_one_bus())
            zero_bus = make_zero_bus()
            @board.set_zero_bus(zero_bus)
            add_extra_bus(zero_bus)

            # Generate busses from the IL
            generate_output_buses(circuit_outputs)
            generate_inputs(circuit_inputs, circuit_nizk_inputs)

            # Generate FieldOps from buses
            layout_buses()

            # Generate output file from Field
            write_to_file(output_filename)
        end

        abstract def make_zero_bus()

        def make_req (expr, trace_type : String) : BaseReq
            case expr
            when .is_a? BitAnd
                result = BitAndReq.new(self, expr.as(BitAnd), trace_type)
            when .is_a? BitOr
                result = BitOrReq.new(self, expr.as(BitOr), trace_type)
            when .is_a? BitNot
                result = BitNotReq.new(self, expr.as(BitNot), trace_type)
            when .is_a? LogicalNot
                result = LogicalNotReq.new(self, expr.as(LogicalNot), trace_type)
            when .is_a? Xor
                result = XorReq.new(self, expr.as(Xor), trace_type)
            when .is_a? LeftShift
                result = LeftShiftReq.new(self, expr.as(LeftShift), trace_type)
            when .is_a? RightShift
                result = RightShiftReq.new(self, expr.as(RightShift), trace_type)
            else
                raise "Not supported expr: #{expr}"
            end
            return result
        end

        abstract def type : Int32

        def generate_output_buses(circuit_outputs)
            i = 0
            circuit_outputs.each do |output|
                name, expr = output
                expression_bus = collapse_tree(make_req(expr, type()).as(BaseReq))
                out_bus = make_output_bus(expression_bus, i)
                i += 1
                add_extra_bus(out_bus)
            end
        end

        def generate_inputs(circuit_inputs, circuit_nizk_inputs)
            circuit_inputs.each do |input|
                expr = input
                req = make_input_req(expr)
                begin
                    bus = lookup(req).as(ArithmeticInputBaseBus)
                    bus.set_used(true)
                rescue
                    bus = collapse_tree(req).as(ArithmeticInputBaseBus)
                    bus.set_used(true)
                end
            end

            if circuit_nizk_inputs
            circuit_nizk_inputs.each do |input|
                    expr = input
                    req = make_nizk_input_req(expr)
                    begin
                        bus = lookup(req).as(ArithmeticInputBaseBus)
                        bus.set_used(true)
                    rescue
                        bus = collapse_tree(req).as(ArithmeticInputBaseBus)
                        bus.set_used(true)
                    end
                end
            end
        end

        def add_extra_bus (bus)
            if bus
                @buses << bus
            else
                raise "Bus must be specified in order to be added"
            end
        end

        def get_board 
            return @board
        end

        def collapser
            return self
        end

        def collapse_impl(key)
            if bus = key.collapse_impl()
                @buses << bus
                return bus.as(Bus)
            else
                raise "Can't collapse #{key}"
            end
        end

        def get_dependencies(key : BaseReq) : Array(BaseReq)
            return key.get_dependencies()
        end

        def layout_buses
            @total_wire_count = 0
            @bus_list = @buses.to_a.sort()
            @bus_list.each do |bus|
                bus_wires = bus.get_wire_count()
                allocated_wires = Array(Wire).new()
                (@total_wire_count..@total_wire_count+bus_wires-1).each do |i|
                    allocated_wires << Wire.new(i)
                end

                @total_wire_count += bus_wires
                bus.assign_wires(WireList.new(allocated_wires))
            end
        end

        def write_to_file (filename)
            tmp_file = File.tempfile(".tmp") do |file|
                file.print("total #{@total_wire_count}\n")
                @bus_list.each do |bus|
                    bus.get_field_ops.each do |field_op|
                        file.print("#{field_op.to_s()}\n")
                    end
                end
            end 
            File.write(filename, File.read(tmp_file.path()))
            tmp_file.delete
        end
    end
end