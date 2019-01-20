require "file"
require "./spec_helper"
require "../src/parser.cr"
require "../src/clangutils.cr"

describe Isekai do
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
            output->x = (input->a + 10) == (input->b * 20);
        }");
    end

    parser = Isekai::CParser.new(tempfile.path(), "", 100, 32, false)
    parser.parse()
    tempfile.delete()
    pp parser.@parsed
end
