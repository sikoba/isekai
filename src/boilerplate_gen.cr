require "clang"

class ScalarField
    def initialize (@name : String)
    end

    getter name
end

class ArrayField
    def initialize (@name : String, @nelems : Int32)
    end

    getter name, nelems
end

alias Field = ScalarField | ArrayField

class StructDecl
    @name : String
    @fields = [] of Field

    getter name, fields

    def initialize (@name : String)
    end

    def add_field (field : Field)
        @fields << field
        self
    end

    def to_s (io)
        io << "struct " << @name
        self
    end
end

class Program
    @struct_decls = [] of StructDecl

    def initialize ()
    end

    def add_struct_decl (decl : StructDecl)
        @struct_decls << decl
        self
    end

    def add_field_to_last_struct (field : Field)
        @struct_decls.last.add_field(field)
        self
    end

    def find_struct_by_name (name : String) : StructDecl?
        @struct_decls.each do |s|
            return s if s.name == name
        end
    end
end

def bake_field (cursor) : Field
    name = cursor.spelling
    type = cursor.type
    if type.kind.constant_array?
        return ArrayField.new(name: name, nelems: type.array_size.to_i32)
    else
        return ScalarField.new(name: name)
    end
end

def visit (program, parent)
    parent.visit_children do |cursor|
        case cursor.kind
        when .struct_decl?
            program.add_struct_decl(StructDecl.new(name: cursor.spelling))
        when .field_decl?
            program.add_field_to_last_struct(bake_field(cursor))
        end
        visit(program, cursor)
        Clang::ChildVisitResult::Continue
    end
end

class CodeGen
    private class Variable
        def initialize (@name : String, @type : StructDecl | String)
        end

        def to_s (io)
            io << @name
            self
        end

        getter name, type
    end

    @var_counter = 0

    private def gen_var_name! : String
        "V#{@var_counter += 1}"
    end

    def initialize ()
    end

    def create_var (type, initializer = nil) : Variable
        name = gen_var_name!
        if initializer
            puts "#{type} #{name} = #{initializer};"
        else
            puts "#{type} #{name};"
        end
        Variable.new(name: name, type: type)
    end

    def traverse_var (v : Variable)
        type = v.type
        raise "Cannot traverse scalar variable" unless type.is_a? StructDecl
        type.fields.each do |field|
            case field
            when ScalarField
                yield "#{v}.#{field.name}"
            when ArrayField
                i_name = gen_var_name!
                puts "for (int #{i_name} = 0; #{i_name} < #{field.nelems}; ++#{i_name}) {"
                yield "#{v}.#{field.name}[#{i_name}]"
                puts "}"
            else
                raise "unreachable"
            end
        end
    end

    def read_input (into expr)
        puts "#{expr} = test_read();"
        self
    end

    def write_output (expr)
        puts "test_write(#{expr});"
        self
    end

    def reference (expr) : String
        "&#{expr}"
    end

    def invoke_func (name, args)
        puts "#{name}(#{args.join ", "});"
        self
    end

    def create_program
        puts <<-END
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

static uint64_t test_read(void)
{
    static unsigned next_index = 0;
    unsigned i;
    unsigned long v;
    if (scanf("%u %lx", &i, &v) != 2) {
        fprintf(stderr, "Cannot read next index-value pair.");
        abort();
    }
    if (i != next_index) {
        fprintf(stderr, "Expected next index %u, got %u.", next_index, i);
        abort();
    }
    ++next_index;
    return v;
}

// This is required since signed values get sign-extended to uint64_t, but we
// want zero-extend.
#define test_write(X) test_write_impl(X, sizeof(X) * 8)

static void test_write_impl(uint64_t v, int nbits)
{
    static char buf[64 + 1];
    for (int i = 0; i < 64; ++i) {
        const int bit = (i < nbits) ? ((v >> i) & 1) : 0;
        buf[64 - 1 - i] = '0' + bit;
    }
    puts(buf);
}

int main()
{
END
        yield
        puts <<-END
    return 0; // tcc miscompiles the program without this
}
END
        self
    end
end

def main
    options =
        Clang::TranslationUnit.default_options |
        Clang::TranslationUnit::Options::DetailedPreprocessingRecord |
        Clang::TranslationUnit::Options::SkipFunctionBodies

    if ARGV.empty?
        STDERR.puts "USAGE: boilerplate_gen [<clang args>...] <C source file>"
        exit 2
    end
    args, file_name = ARGV[...-1], ARGV[-1]
    index = Clang::Index.new
    files = [Clang::UnsavedFile.new(file_name, File.read(file_name))]
    tu = Clang::TranslationUnit.from_source(index, files, args, options)

    program = Program.new
    visit(program, tu.cursor)

    input_struct = program.find_struct_by_name "Input"
    raise "Cannot find the 'Input' struct" unless input_struct

    output_struct = program.find_struct_by_name "Output"
    raise "Cannot find the 'Output' struct" unless output_struct

    nizk_input_struct =
        program.find_struct_by_name("NzikInput") ||
        program.find_struct_by_name("NizkInput")

    code_gen = CodeGen.new
    code_gen.create_program do
        in_var = code_gen.create_var(type: input_struct)
        out_var = code_gen.create_var(type: output_struct, initializer: "{0}")

        code_gen.traverse_var(in_var) { |e| code_gen.read_input into: e }

        if nizk_input_struct
            nizk_var = code_gen.create_var(type: nizk_input_struct)
            # read the one-input
            code_gen.read_input(into: code_gen.create_var(type: "int"))
            code_gen.traverse_var(nizk_var) { |e| code_gen.read_input into: e }
            outsource_args = [in_var, nizk_var, out_var]
        else
            outsource_args = [in_var, out_var]
        end
        code_gen.invoke_func("outsource", outsource_args.map { |e| code_gen.reference e })

        code_gen.traverse_var(out_var) { |e| code_gen.write_output e }
    end
end

main
