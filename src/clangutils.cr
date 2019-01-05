require "clang"

module Isekai
    # Auxilary wrappers for the libclang cursors
    # Provides helpers around the common methods
    # on the libclang interface
    class ClangUtils
      # Extracts the function's body (a cursor to CompoundStmt)
      # from the function definition cursor
      #
      # Parameters:
      #    function_cursor = Clang::Cursor representing the function
      #
      # Returns:
      #    compound statement representing the function's body
      def self.findFunctionBody (function_cursor)
          function_body_cursor = nil
          function_cursor.visit_children do |cursor|
              case cursor.kind
              when .compound_stmt?
                  function_body_cursor = cursor
                  next Clang::ChildVisitResult::Break
              else
                  next Clang::ChildVisitResult::Continue
              end
          end
          function_body_cursor
      end

      # For the given cursor to an expression, return
      # the cursor to the concrete expression, skipping
      # potential FirstExpr (which is a marker AST node)
      #
      # Params:
      #     cursor = cursor to the expression
      # Returns:
      #     the concrete expression, unwrapping the FirstExpr
      #     marker layer
      def self.getConcreteExpression (cursor)
          if !cursor.kind.first_expr?
              return cursor
          end

          result = nil
          cursor.visit_children do |child|
              case child.kind
              when .first_expr?
                  next Clang::ChildVisitResult::Continue
              else
                  result = child
                  next Clang::ChildVisitResult::Break
              end
          end

          # Never return Nil, raise if not found
          if cur_res = result
              return cur_res
          else
              raise "Can't resolve FirstExpr"
          end
      end

      # Dumps the AST from the cursor to stdout.
      def self.dumpCursorAst (cursor_instance)
          if cursor = cursor_instance
              puts "* #{cursor}"
              cursor.visit_children do |child|
                  puts "- Child #{child}"
                  next Clang::ChildVisitResult::Recurse
              end
            else
                puts "Cursor Nil"
            end
      end

      # Returns the operands used in the binary operation
      #
      # Params:
      #     cursor = binary operator expression
      #
      # Returns:
      #     an array with two members representing two
      #     operands in the binary operation
      #
      def self.getBinaryOperatorExprs (cursor)
          result = Array(Clang::Cursor).new
          cursor.visit_children do |child|
              result << child
              next Clang::ChildVisitResult::Continue
          end

          raise "Error parsing binary operator #{cursor}" unless result.size == 2

          return result
      end

      # Returns the condition, then branch and else branch for the
      # if-statement
      #
      # Params:
      #     cursor = cursor pointing to the if statement
      #
      # Returns:
      #     an array containing the following elements of the if statement:
      #         1. condition
      #         2. then body
      #         3. (optional) else body
      #
      def self.getIfStatementExprs (cursor)
          result = Array(Clang::Cursor).new
          cursor.visit_children do |child|
              result << child
              next Clang::ChildVisitResult::Continue
          end

          if (result.size < 2 || result.size > 3)
              raise "Unexpected number of children for if statement op. #{cursor}"
          end

          return result
      end

      # Extracts the function parameters from the function declaration
      #
      # Params:
      #     func_decl_cursor = cursor pointing to the functiond declaration
      #
      # Returns:
      #     an array with cursors representing the function parameters
      #
      def self.findFunctionParams (func_decl_cursor)
          result = Array(Clang::Cursor).new
          func_decl_cursor.visit_children do |child|
              if child.kind.parm_decl?
                  result << child
              end
              next Clang::ChildVisitResult::Continue
          end

          return result
      end

      # Gets the first child for the given cursor - an utility
      # to wrap very common operating during the code transformation
      #
      # Params:
      #    cursor = cursor to extract the child cursor from
      #
      # Returns:
      #    the cursor to the first child node of the input cursor
      #
      def self.getFirstChild (cursor)
          result = nil

          cursor.visit_children do |child|
              result = child
              next Clang::ChildVisitResult::Break
          end

          return result
      end

      # Gets the cursor to the type reference for the given
      # variable declaration.
      #
      # Params:
      #    cursor = cursor to the variable declaration
      #
      # Returns:
      #    a cursor to TypeRef node referring to the type
      #    of the variable that's being declared
      #
      def self.getTypeRefChild (cursor)
          typeref_cursor = nil
          cursor.visit_children do |child|
              case child.kind
              when .type_ref?
                  typeref_cursor = child
                  Log.log.warn "Found type_ref child: #{typeref_cursor}"
                  next Clang::ChildVisitResult::Break
              else
                  next Clang::ChildVisitResult::Continue
              end
          end

          return typeref_cursor
      end

      # Returns the dimension of the array
      #
      # Params:
      #     cursor = array cursor
      #
      # Returns:
      #     declared number of the elements in the array
      #
      def self.getArrayDimension (cursor)
          if cursor.is_a? Clang::Type
              return cursor.num_elements.to_i32
          else
              return cursor.type.num_elements.to_i32
          end
          return -1
      end

      # Extracts the struct fields from the struct.
      #
      # Params:
      #    struct_cursor = cursor pointing to the struct definition
      #
      # Returns:
      #    an array of the struct fields
      #
      def self.getStructFields (struct_cursor)
          struct_fields = Array(Clang::Cursor).new
          struct_cursor.visit_children do |child|
              case child.kind
              when .field_decl?
                  struct_fields << child
                  Log.log.warn "Found struct field child: #{child}"
              end
              next Clang::ChildVisitResult::Continue
          end
          return struct_fields
      end

      # Gets the value for the literal
      #
      # Params:
      #     cursor = literal cursor
      #
      # Returns:
      #     value of the literal behind the cursor
      #
      def self.getValue (cursor)
          result = nil
          case cursor.kind
          when .integer_literal?
              result = cursor.literal.to_i
          else
              raise "Getting value of the non-literal"
          end
          return result
      end


      # Gets the initializer for the variable.
      #
      # Params:
      #    cursor = variable declaration cursor
      #
      # Returns:
      #    the literal value for the initializer
      #
      # Raises an error if the variable doesn't have constant
      # initializer
      def self.getVariableInitializer (cursor : Clang::Cursor)
          result = nil
          if result = getValue(cursor)
              return result
          end

          if child = getFirstChild(cursor)
              if result = getValue(child)
                  return result
              end
          end

          if result.is_a? Nil
              dumpCursorAst(cursor)
              raise "Can't get the initializer: #{cursor}"
          else
              return result
          end
      end


      # Checks if the variable declaration has an initializer
      #
      # Params:
      #    cursor = variable declaration cursor
      #
      # Returns:
      #    true if the variable declaration has an initializer
      #
      def self.hasInitilizer (var_decl_cursor : Clang::Cursor)
          result = false
          var_decl_cursor.visit_children do |child|
              result = true
              Clang::ChildVisitResult::Break
          end
          return result
      end
    end
end
