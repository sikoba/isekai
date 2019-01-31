require "./wire"
require "./fieldops"

module Isekai

# Adds support for the zero-equals gate
class FieldZeroP < FieldOp
        def initialize(@comment, @in_wire : Wire, @out_wire : Wire, @m_wire : Wire?)
                super(@comment)
        end

        def field_command()
            if m_wire = @m_wire
                return "zerop in #{WireList.new([@in_wire])} out #{WireList.new([m_wire, @out_wire])}"
            else
                return "zerop in #{WireList.new([@in_wire])} out #{WireList.new([@out_wire])}"
            end
        end

        def input_wires()
            return WireList.new([@in_wire])
        end

        def output_wires()
            return WireList.new([@out_wire])
        end
    end

class FieldConstMul < FieldOp
	def initialize(@comment, @value : Int32, @in_wire : Wire, @out_wire : Wire)
		super(@comment)
    end

	def field_command()
		if (@value >= 0)
			constant = "#{@value.to_s(16)}"
		else
            constant = "neg-#{(-@value).to_s(16)}"
        end
        return "const-mul-#{constant} in #{WireList.new([@in_wire])} out #{WireList.new([@out_wire])}"
    end

    def input_wires()
        return WireList.new([@in_wire])
    end

    def output_wires()
        return WireList.new([@out_wire])
    end
end

class FieldBinaryOp < FieldOp
	def initialize(@comment, @verb : String, @in_list : WireList, @out_list : WireList)
		super(@comment)
    end

	def field_command()
        return "#{@verb} in #{@in_list} out #{@out_list}"
    end

    def input_wires() 
        return @in_list
    end

    def output_wires()
        return @out_list
    end
end

class FieldAdd < FieldBinaryOp
	def initialize(@comment, @in_list : WireList, @out_list : WireList)
		super(@comment, "add", @in_list, @out_list)
    end
end

class FieldMul < FieldBinaryOp
    def initialize(@comment, @in_list : WireList, @out_list : WireList)
		super(@comment, "mul", @in_list, @out_list)
    end
end

class FieldSplit < FieldBinaryOp
    def initialize(@comment, @in_list : WireList, @out_list : WireList)
		super(@comment, "split", @in_list, @out_list)
    end
end
end