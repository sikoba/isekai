require "json"
require "big.cr"

module Isekai
    
class R1CS

    def initialize(@bit_width : Int32)

    end
    ###load inputs file (json), and add/update the result 
    def postprocess(r1csInputsfile, input_nb)
        json = File.open(r1csInputsfile) do |file|        #TODO handle errors 
            result = JSON.parse(file)
            file.close()
            result
        end
        inputs = Array(Int32|Int64).new
        outputs = Array(Int32|Int64).new
       
        i = 0
        json["inputs"].as_a.each do |val_str|
            val = BigInt.new(val_str.as_s)         
            if (i<input_nb)
                inputs.push(decomplement(val))
            elsif (i > input_nb) #We ignore the '1' constant. TODO: when we will build the r1cs ourself, the 1 constant will not be there anymore
                outputs.push(decomplement(val))    #last values are for the output
            end
            i+=1
        end
     
        #We re-create the results field and overwrites it
        str_res = JSON.build do |json|
            json.object do
                json.field "inputs", inputs.to_json
                json.field "outputs", outputs.to_json
            end
        end
        json.as_h["results"] = JSON.parse(str_res)      #There must be a better way..

        file = File.open(r1csInputsfile, mode="w")    #TODO we are just updating one part of the file no need to write everything
        json.to_json(file)
        file.close()
       
    end

    def decomplement(val)
        # p-complement ...TODO.. p should be the prime number of the r1cs field
        # if p-complement:
        #if (p-val<val)
        #    val = val-p    
        #end
        if (@bit_width == 64)
            return val.to_i64
        end
        return val.to_i     #TODO we support only bit_width 32 or 64?
    end

end

end