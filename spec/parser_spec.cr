require "./spec_helper"
require "../src/parser.cr"

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
end
