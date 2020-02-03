require "clang"

def create_program (&block)
    puts <<-END
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

void _unroll_hint(unsigned n) { (void) n; }
void _unroll_hint_once(unsigned n) { (void) n; }
void _unroll_hint_once_pop(void) {}

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
    return 0;
}
END
end

def visit_fields (type : Clang::Type, &block : Clang::Cursor -> LibC::CXVisitorResult)
    LibC.clang_Type_visitFields(
        type,
        ->(cursor, data) {
            proc = Box(typeof(block)).unbox(data)
            proc.call(Clang::Cursor.new(cursor))
        },
        Box.box(block))
end

def traverse_var (type : Clang::Type, name : String, &block : String ->)
    case type.kind
    when .constant_array?
        i_name = "i#{name.size}"
        puts "for (int #{i_name} = 0; #{i_name} < #{type.array_size}; ++#{i_name}) {"
        traverse_var(type.element_type, "#{name}[#{i_name}]", &block)
        puts "}"
    when .record?, .elaborated?
        visit_fields(type) do |cursor|
            traverse_var(cursor.type, "#{name}.#{cursor.spelling}", &block)
            LibC::CXVisitorResult::Continue
        end
    else
        yield name
    end
end

class Program
    def initialize (
        @input_struct : Clang::Cursor,
        @nizk_input_struct : Clang::Cursor?,
        @output_struct : Clang::Cursor)
    end
end

def parse_program_from_argv : Program
    options = Clang::TranslationUnit.default_options
    options &= ~Clang::TranslationUnit::Options::DetailedPreprocessingRecord
    options |= Clang::TranslationUnit::Options::SkipFunctionBodies

    if ARGV.empty?
        STDERR.puts "USAGE: boilerplate_gen [<clang args>...] <source file>"
        exit 2
    end
    args, file_name = ARGV[...-1], ARGV[-1]
    index = Clang::Index.new
    files = [Clang::UnsavedFile.new(file_name, File.read(file_name))]
    tu = Clang::TranslationUnit.from_source(index, files, args, options)

    input_struct : Clang::Cursor? = nil
    nizk_input_struct : Clang::Cursor? = nil
    output_struct : Clang::Cursor? = nil

    tu.cursor.visit_children do |cursor|
        if cursor.kind.struct_decl?
            case cursor.spelling
            when "Input"
                input_struct = cursor
            when "NizkInput", "NzikInput"
                nizk_input_struct = cursor
            when "Output"
                output_struct = cursor
            end
        end
        Clang::ChildVisitResult::Continue
    end

    raise "Cannot find 'Input' struct" unless input_struct
    raise "Cannot find 'Output' struct" unless output_struct

    Program.new(
        input_struct: input_struct.not_nil!,
        nizk_input_struct: nizk_input_struct,
        output_struct: output_struct.not_nil!)
end

def main
    prog = parse_program_from_argv
    create_program do
        puts "struct #{prog.@input_struct.spelling} input;"
        puts "static struct #{prog.@output_struct.spelling} output;"

        traverse_var(prog.@input_struct.type, "input") { |e| puts "#{e} = test_read();" }

        if (nizk_input_struct = prog.@nizk_input_struct)
            puts "struct #{nizk_input_struct.spelling} nizk_input;"
            # read one-input
            puts "(void) test_read();"
            traverse_var(nizk_input_struct.type, "nizk_input") { |e| puts "#{e} = test_read();" }

            puts "outsource(&input, &nizk_input, &output);"
        else
            puts "outsource(&input, &output);"
        end

        traverse_var(prog.@output_struct.type, "output") { |e| puts "test_write(#{e});" }
    end
end

main
