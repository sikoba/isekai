require "file"
require "./spec_helper"
require "../src/parser.cr"
require "../src/clangutils.cr"

describe Isekai do
    cursor = parse_c_code("void foo(int x, int y)
                                   { 
                                      int z = x + 1; 
                                      if (z == 1) { int w = 0; }
                                      else { int w = 1; }
                                   }")

    func_body = Isekai::ClangUtils.findFunctionBody(cursor)
    raise "findFunctionBody failed" if func_body.is_a? Nil
    func_body.kind.should eq Clang::CursorKind::CompoundStmt

    fun_params = Isekai::ClangUtils.findFunctionParams(cursor)
    fun_params.size.should eq 2

    decl_statement = Isekai::ClangUtils.getFirstChild(func_body)
    raise "Can't find decl statement declaration" if decl_statement.is_a? Nil
    decl_statement.kind.should eq Clang::CursorKind::DeclStmt

    var_decl = Isekai::ClangUtils.getFirstChild(decl_statement)
    raise "Can't find variable declaration declaration" if var_decl.is_a? Nil
    var_decl.kind.should eq Clang::CursorKind::VarDecl

    binary_expr = get_first_child_of_kind(var_decl, Clang::CursorKind::BinaryOperator)
    raise "Can't find binary expression" if binary_expr.is_a? Nil

    binary_elements = Isekai::ClangUtils.getBinaryOperatorExprs(binary_expr)
    binary_elements.size.should eq 2

    # Compile parser
    tempfile = File.tempfile(".c") do |file|
        file.print("
        struct Input {
            int a;
            int b;
        };

        struct Output {
            int x;
        };

        void outsource(struct Input *input, struct Output *output)
        {
          output->x = (input->a + 5) == (input->b * 2);
        }");
    end

    parser = Isekai::CParser.new(tempfile.path(), "", 100, 32, false)
    parser.parse()
    tempfile.delete()

    # test decode type
    symtable = Isekai::SymbolTable.new(nil, nil)
    type = parser.decode_type(var_decl, symtable)
    type.@type.should be_a Isekai::IntType

    cursor = parse_c_code("struct S { int x; unsigned y; };")
    type = parser.decode_type(cursor, symtable)
    type.@type.should be_a Isekai::StructType
    if s = type.@type.as Isekai::StructType
        s.get_field("x").@type.should be_a Isekai::IntType
        s.get_field("y").@type.should be_a Isekai::UnsignedType
    end

    cursor = parse_c_code("int* x;")
    type = parser.decode_type(cursor, symtable)
    type.@type.should be_a Isekai::PtrType
    (type.@type.as Isekai::PtrType).@base_type.should be_a Isekai::IntType

    cursor = parse_c_code("int y[7];")
    type = parser.decode_type(cursor, symtable)
    type.@type.should be_a Isekai::ArrayType
    if arr = type.@type.as Isekai::ArrayType
        arr.@type.should be_a Isekai::IntType
        arr.@size.should eq 7
    end
end
