require "spec"
require "../src/parser.cr"
require "clang"

# Parses the C code and returns libclang cursor
#
# Params:
#     code = C code represented as string
#
# Returns:
#     libclang's cursor representing the input code
def parse_c_code (code : String)
    unsaved_file = Clang::UnsavedFile.new("file.c", code)
    options = Clang::TranslationUnit.default_options
    index = Clang::Index.new

    # 2. Load the file and get the translation unit
    tu = Clang::TranslationUnit.from_source(index, [unsaved_file], [""], options)

    # 3. skip all macro cursors
    real_cursor = tu.cursor
    tu.cursor.visit_children do |child|
        case child.kind
        when .macro_definition?
            next Clang::ChildVisitResult::Continue
        else
            real_cursor = child
            next Clang::ChildVisitResult::Break
        end
    end
    return real_cursor
end

# Gets the first child in the tree of a given kind
#
# Params:
#     cursor = libclang cursor to query the children nodes
#     child_kind = the kind of the child to return
def get_first_child_of_kind (cursor, child_kind)
    real_cursor = nil
    cursor.visit_children do |child|
        case child.kind
        when child_kind
            real_cursor = child
            next Clang::ChildVisitResult::Break
        else
            next Clang::ChildVisitResult::Continue
        end
    end

    return real_cursor
end
