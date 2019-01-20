require "file"
require "./spec_helper"
require "../src/parser.cr"
require "../src/clangutils.cr"

describe Isekai do
    it "Constant folding if expression" do
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
            int x = 5;
            if (x)
                output->x = (input->a + 5) == (input->b * 2);
            else
                output->x = (input->a / 10) == (input->b + 20);
            }");
        end

        parser = Isekai::CParser.new(tempfile.path(), "", 100, 32, false)
        parser.parse()
        tempfile.delete()
        state = parser.parsed_state
        output = state.symtab.lookup(state.expr.as(Isekai::StorageRef).key)

        output.as(Isekai::CmpEQ).@left.as(Isekai::Add).@right.as(Isekai::Constant).@value.should eq 5
        output.as(Isekai::CmpEQ).@right.as(Isekai::Multiply).@right.as(Isekai::Constant).@value.should eq 2
    end

    it "Constant folding if expression - false branch" do
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
            int x = 0;
            if (x)
                output->x = (input->a + 15) == (input->b * 21);
            else
                output->x = (input->a / 10) == (input->b + 20);
            }");
        end

        parser = Isekai::CParser.new(tempfile.path(), "", 100, 32, false)
        parser.parse()
        tempfile.delete()
        state = parser.parsed_state
        output = state.symtab.lookup(state.expr.as(Isekai::StorageRef).key)

        output.as(Isekai::CmpEQ).@left.as(Isekai::Divide).@right.as(Isekai::Constant).@value.should eq 10
        output.as(Isekai::CmpEQ).@right.as(Isekai::Add).@right.as(Isekai::Constant).@value.should eq 20
    end

    it "Constant folding if expression - nonconstant expression" do
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
            int x = input->a;
            if (x)
                output->x = (input->a + 15) == (input->b * 21);
            else
                output->x = (input->a / 10) == (input->b + 20);
            }");
        end

        parser = Isekai::CParser.new(tempfile.path(), "", 100, 32, false)
        parser.parse()
        tempfile.delete()
        state = parser.parsed_state
        output = state.symtab.lookup(state.expr.as(Isekai::StorageRef).key)
        output.as(Isekai::Conditional).@valfalse
            .as(Isekai::CmpEQ).@left
                .as(Isekai::Divide).@right
                    .as(Isekai::Constant).@value.should eq 10
    end

    it "Constant folding for loop - single body exec" do
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
                int x = 5;

                for (x = 1; x != 0; x = 0)
                {
                    output->x = x + 10;
                }
            }");
        end

        parser = Isekai::CParser.new(tempfile.path(), "", 100, 32, false)
        parser.parse()
        tempfile.delete()
        state = parser.parsed_state
        output = state.symtab.lookup(state.expr.as(Isekai::StorageRef).key)
        output.as(Isekai::Add).@left
             .as(Isekai::Constant).@value.should eq 1
        output.as(Isekai::Add).@right
             .as(Isekai::Constant).@value.should eq 10
    end


    it "Constant folding for loop - no body exec" do
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
                int x = 5;

                for (x = 1; x == 0; x += 10)
                {
                    output->x = x + 10;
                }
            }");
        end

        parser = Isekai::CParser.new(tempfile.path(), "", 100, 32, false)
        parser.parse()
        tempfile.delete()
        state = parser.parsed_state
        output = state.symtab.lookup(state.expr.as(Isekai::StorageRef).key)
        output.as(Isekai::Constant).@value.should eq 0
    end
end
