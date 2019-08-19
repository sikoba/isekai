require "./board.cr"
require "./busreq.cr"
require "./bus.cr"
require "../common/collapser.cr"
require "../common/dfg.cr"

module Isekai::Backend
    # Request factory - the core of the backend. This Collapser recursively converts
    # all dependencies of the output into the Buses.
    # The translation from DFGExpr into BusReq is inside make_req.
    abstract class RequestFactory < Collapser(BaseReq, Bus)
        def initialize(@output_filename : String, @circuit_inputs : Array(DFGExpr), @circuit_nizk_inputs : Array(DFGExpr)|Nil,
                @circuit_outputs : Array(Tuple(StorageKey, DFGExpr)), @bit_width, @circuit_inputs_val : Array(Int32))
            super()

            # lay down the board, one and zero buses
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

            # Generate input file from Field
            write_inputs_to_file("#{output_filename}.in")   #todo remove .arith extension
        end

        # Differs for arithmetic and boolean circuits.
        abstract def make_zero_bus()

        # Maps DFGExpr into the BusRequest (which ultimatively yields bus.)
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
            when .is_a? ZeroExtend # FIXME
                result = make_req(expr.@expr, trace_type)
            else
                raise "Not supported expr: #{expr}"
            end
            return result
        end

        # Type of the factory.
        abstract def type : Int32

        # for every output, recursively generate buses.
        def generate_output_buses(circuit_outputs)
            i = 0
            circuit_outputs.each do |output|
                name, expr = output       
                expression_bus = collapse_tree(make_req(expr, type()).as(BaseReq))      
                out_bus = make_output_bus(expression_bus, i)    
                i += 1;
                add_extra_bus(out_bus)
            end
        end

        # Genenerate inputs if not connected for the normalization.
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

        # if request yielded a bus, add it.
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

        # Sorts down the buses based on the ordering (see Bus' documentation)
        # allocate wires and connects the buses.
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

        # Writes buses into the file, one bus per line.
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

        # Writes inputs into the file, one variable per line.
        def write_inputs_to_file (filename)
            tmp_file = File.tempfile(".tmp") do |file|
                # variables: circuit_inputs/ constant / circuit_nizk_inputs / LOGIC / circuit_outputs.size
                #TODO What about LOGIC variables?
                #arith file: inputs +1
                i = 0;
                @circuit_inputs.each do |circuit_in|
                    val = 0;
                    if i < @circuit_inputs_val.size
                        val = @circuit_inputs_val[i];
                    end
                    file.print("#{i} #{val.to_u32.to_s(16)}\n")  #No value..yet...
                    i += 1                   
                end
                file.print("#{i} 1\n")      # the ONE constant
                ni = i
                i += 1
                if nzik = @circuit_nizk_inputs
                    nzik.each do |circuit_in|
                        val = 0;
                        if ni < @circuit_inputs_val.size
                            val = @circuit_inputs_val[ni];
                        end
                        file.print("#{i} #{val.to_u32.to_s(16)}\n")  #No value..yet...
                        i += 1  
                        ni += 1                 
                    end
                end
            end 
            # FileUtils.mv(tmp_file.path(), filename) # generates error when moving files between different filesystems 
            FileUtils.cp(tmp_file.path(), filename)
            FileUtils.rm(tmp_file.path())

        end
    end
end
