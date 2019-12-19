require "json"
require "big.cr"
require "./gate.cr"

module Isekai
    
##################### maths
class Maths

    #modular exponentiation: a^exp [mod]
    def modulo_exp(a : BigInt, exp : BigInt, mod : BigInt)
      res = BigInt.new(1);
      while (exp > 0)
        if ((exp & 1) > 0)
          res = (res*a).modulo(mod);
        end
        exp >>= 1;
        a = (a*a).modulo(mod)
      end
      return res;
    end

    #inverse of a modulo mod -WARNING this function only works if mod is prime
    def modulo_inverse(a : BigInt, mod : BigInt)
        return modulo_exp(a, mod-2, mod);     #TODO   anybetter inverse? 
    end
end

class R1CS
    @gate_keeper : GateKeeper | Nil

    def initialize(@bit_width : Int32)

    end

    def set_gate(gate)
        @gate_keeper = gate
    end

    def gate
        if (g = @gate_keeper)
            return g;
        end
        raise  Exception.new("Gate keeper must be defined!!")
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
        str_res = decomplement2_json(json["inputs"].as_a, input_nb)
      
        json.as_h["results"] = JSON.parse(str_res)      #There must be a better way..

        file = File.open(r1csInputsfile, mode="w")    #TODO we are just updating one part of the file no need to write everything
        json.to_json(file)
        file.close()
    end

    #same as decomplement_json but is working from libsnark r1cs.in inputs, it is keep ony for legacy
    def decomplement2_json(input_val : Array, input_nb)

        inputs = Array(Int32|Int64).new
        outputs = Array(Int32|Int64).new
           
        i = 0
        input_val.each do |val_str|
            val = BigInt.new(val_str.as_s)         
            if (i<input_nb)
                inputs.push(decomplement(val))
            elsif (i > input_nb)            #ONE-CONSTANT
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
        return str_res    
    end
    ##decomplement the values of public inputs from the r1cs.in file, into a 'decomplemented' inputs/outputs json
    def decomplement_json(input_val : Array(String), input_nb)

        inputs = Array(Int32|Int64).new
        outputs = Array(Int32|Int64).new
           
        i = 0
        input_val.each do |val_str|
            val = BigInt.new(val_str)         
            if (i<input_nb)
                inputs.push(decomplement(val))
            elsif (i >= input_nb) 
                pp "DECOMPLEMENT-" + val_str
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
        return str_res    
    end

    def decomplement(val)
        # p-complement ...TODO.. p should be the prime number of the r1cs field
        # if p-complement:
        #if (p-val<val)
        #    val = val-p    
        #end
        if (@bit_width == 64)
            return val.to_i64!
        end
        return val.to_i!     #TODO we support only bit_width 32 or 64?
    end

    #inputs and witnesses json from arrays
    def inputs_to_json(inputs : Array(String), witnessess : Array(String))
        str_res = JSON.build do |json|
            json.object do 
                json.field "inputs", to_json(inputs)
                json.field "witnesses", to_json(witnessess)
            end
        end
        return str_res;
    end
  
    
    #generate the header for the j-r1cs file
    def json_header(constraint_nb : Int32, prime : BigInt, instance_nb : UInt32, witness_nb : Int32)
        #header is limited to 2048 characters because we are updating it after the file has been written. It should be safe and anyway it is easy to change.
        header = "{\"r1cs\":{\"constraint_nb\":#{constraint_nb},\"extension_degree\":1,\"field_characteristic\":\"#{prime}\",\"instance_nb\":#{instance_nb},\"version\":\"1.0\",\"witness_nb\":#{witness_nb}}}"
        if (header.size > 2048)
            raise "ERROR - Header too big!"
        end
        header += " "*(2048-header.size)
    end
  
    #generate the json for one constraint a*b=c
    def to_json_str(a : Array(Tuple(UInt32,BigInt)), b : Array(Tuple(UInt32,BigInt)), c : Array(Tuple(UInt32,BigInt)))
        str_res = JSON.build do |json|
            json.object do 
                json.field "A", to_json(a);
                json.field "B", to_json(b);
                json.field "C", to_json(c);
            end
        end
        return str_res;
    end
  
    #generate the json string of a linear combination
    #we need a gate keeper to convert the wire into its r1cs variable index
    def to_json(lc : Array(Tuple(UInt32,String)))
        str = JSON.build do |json|
            json.array do
                lc.each do |item|
                    json.array do
                    json.number @gate_keeper.getWireIdx(item[0])
                    json.string item[1]
                    end
                end
            end
        end
        return JSON.parse(str)      #TODO it must be possible to generate the json directly
    end


        #generate the json for one constraint a*b=c
    def to_json_str_raw(a : Array(Tuple(UInt32,BigInt)), b : Array(Tuple(UInt32,BigInt)), c : Array(Tuple(UInt32,BigInt)))
            str_res = JSON.build do |json|
                json.object do 
                    json.field "A", to_json_raw(a);
                    json.field "B", to_json_raw(b);
                    json.field "C", to_json_raw(c);
                end
            end
            return str_res;
        end
    def to_json_raw(lc : Array(Tuple(UInt32,String)))
        str = JSON.build do |json|
            json.array do
                lc.each do |item|
                    json.array do
                    json.number item[0]
                    json.string item[1]
                    end
                end
            end
        end
        return JSON.parse(str)      #TODO it must be possible to generate the json directly
    end
    def to_json_raw(lc : Array(Tuple(UInt32,BigInt)))
        str = JSON.build do |json|
            json.array do
                lc.each do |item|
                    json.array do
                        json.number item[0]
                        json.string item[1].to_s
                    end
                end
            end
        end
        return JSON.parse(str)      #TODO it must be possible to generate the json directly
    end
  
    #serialize an arry of string into json. Using directly to_json from the array escape the strings...why?? \"...\"
    def to_json(a : Array(String))
        str = JSON.build do |json|
            json.array do
                a.each do |item|
                    json.string item
                end
            end
        end
        return JSON.parse(str)      #TODO it must be possible to generate the json directly
    end
  
    #generate the json string of a linear combination (same as the other function but this one uses bigint)
    #we need a gate keeper to convert the wire into its r1cs variable index
    def to_json(lc : Array(Tuple(UInt32,BigInt)))
        str = JSON.build do |json|
            json.array do
                lc.each do |item|
                    json.array do
                        json.number gate.getWireIdx(item[0])
                        json.string item[1].to_s
                    end
                end
            end
        end
        return JSON.parse(str)      #TODO it must be possible to generate the json directly
    end
  
    def to_json(lc : LinearCombination)
        return to_json(lc.@lc);
    end
  
end

end