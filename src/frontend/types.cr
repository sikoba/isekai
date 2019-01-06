require "./symbol_table_value.cr"

module Isekai

# A common ansector class for all types in the program.
# We know four type classes: a void type - a result of
# an expression with no value; integer/unsigned type;
# an array type - the array containing fixed number of
# elements of the same type; and a struct - the record
# containing the fixed number of different types, accessible
# by fields. The last type is a pointer type which is a type
# that references another type.
class Type < SymbolTableValue
end

# The signed integer type.
class IntType < Type
    # Returns the size of the type.
    def sizeof
        return 1
    end
end

# The unsigned integer type.
class UnsignedType < IntType
    # Returns the size of the type.
    def sizeof
        return 1 
    end
end

# Array type. Contains fixed number elements of a single type.
class ArrayType < Type
    # Constucts an array.
    # Params:
    #     type = type of the array's elements
    #     size = number of the array's elements 
    def initialize (@type : Type, @size : Int32)
    end
end

# Struct field. A single field in a struct referencable
# by its name.
class StructField
    # Constructs an struct field
    # Params:
    #     type = field type
    #     label = struct field's label (also known as field name)
    def initialize (@type : Type, @label : String)
    end
end

# Struct type. A structured record consisted by the number
# of StructFields.
class StructType < Type
    # Array of the struct fields' offsets in the memory.
    # All fields in a structs are stored inside a contigous block
    # of memory. Every field is stored at the offset that's a sum
    # of all previous fields' size. This array has an element for
    # every struct's field and it's representing the field's offset
    # in memory.
    @offsets : Array(Int32)

    # Constructs a struct.
    # Params:
    #     label = name of the struct type
    #     fields = array of struct fields.
    def initialize (@label : String, @fields : Array(StructField))
        # Reserve the memory for the offests. The last
        # element of the offsets array is the offset of the end
        # of the struct (the sum of all fields' types' sizes).
        @offsets = [0] * (fields.size + 1)
            
        # Caclulate the offsets for every field.
        # Offests(i+1) = Offsets(i) + Field(i).sizeof
        (0..@offsets.size-2).each do |i|
            @offsets[i+1] = @offsets[i] + @fields[i].@type.sizeof
        end
    end

    # Returns the size of the structure.
    def sizeof
        # the size of the structure is the same as the last offset.
        return @offsets[-1]
    end

    # Returns the offset of the particular field
    # Params:
    #     field_label = label of the field to lookup
    # Returns:
    #     the offset of the struct's field
    def offsetof(field_label)
        return @offsets[indexof(field_label)]
    end

    # Returns the value of the particular field
    # Params:
    #     field_label = label of the field to lookup
    # Returns:
    #     the value of the struct's field
    def get_field(field_label)
        return @fields[indexof(field_label)]
    end

    # Gets the index of the field in the value and offest's
    # array.
    #
    # Params:
    #     field_label = label of the field to lookup
    # Returns:
    #     the index of the struct's field determined by the label.
    #
    private def indexof (field_label)
        result : StructField|Nil = nil
        i = 0
        index = 0

        # Perform a linear search in the fields array
        @fields.each do |field|
            if field.@label == field_label
                index = i 
                result = field
                break
            end
            i += 1
        end
        if result.is_a? Nil
            raise "No such struct field"
        end

        return index
    end
end

# Pointer type. References another (base) type.
class PtrType < Type
    # Constructs the pointer type.
    #
    # Params:
    #     base_type = base type which this pointer references.
    def initialize (@base_type : Type)
    end
end
end
