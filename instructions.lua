--!native
-- Normally, strict would be here, but I can't debug my code for shit!
--!optimize 2

local cpu_memory = require("cpu_and_memory")
local decoder_module = require("decoder")

export type Instruction = {
    opcode: number,
    size: number,
    operands: {decoder_module.Operand}
}

type InstructionHandler = (cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: Instruction) -> ()

local function get_operand_value(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, operand: decoder_module.Operand): number
    if operand.type == "register" then
        return cpu_memory.get_register_value(cpu, operand.value)
    elseif operand.type == "immediate" then
        return operand.value
    elseif operand.type == "memory" then
        return cpu_memory.read_memory(memory, operand.value, 4)
    else
        error("Invalid operand type")
    end
end

local function set_operand_value(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, operand: decoder_module.Operand, value: number)
    if operand.type == "register" then
        cpu_memory.set_register_value(cpu, operand.value, value)
    elseif operand.type == "memory" then
        cpu_memory.write_memory(memory, operand.value, value, 4)
    else
        error("Invalid operand type for setting value")
    end
end

local function update_flags(cpu: cpu_memory.CPU, result: number, src: number, dest: number)
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.ZF, result == 0)
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.SF, bit32.btest(result, 0x80000000))
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.CF, result < 0 or result > 0xFFFFFFFF)
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.OF, 
        (bit32.bxor(bit32.rshift(src, 31), bit32.rshift(dest, 31)) == 0) and
        (bit32.bxor(bit32.rshift(result, 31), bit32.rshift(src, 31)) == 1)
    )
end

local function mov(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local value = get_operand_value(cpu, memory, src)
    set_operand_value(cpu, memory, dest, value)
end

local function add(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = dest_value + src_value
    set_operand_value(cpu, memory, dest, bit32.band(result, 0xFFFFFFFF))
    update_flags(cpu, result, src_value, dest_value)
end

local function sub(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = dest_value - src_value
    set_operand_value(cpu, memory, dest, bit32.band(result, 0xFFFFFFFF))
    update_flags(cpu, result, src_value, dest_value)
end

local function jmp(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: Instruction)
    local offset = get_operand_value(cpu, memory, instruction.operands[1])
    cpu.ip = cpu.ip + offset
end

local function push(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: Instruction)
    local value = get_operand_value(cpu, memory, instruction.operands[1])
    cpu.registers[5].value = cpu.registers[5].value - 4 -- Decrement ESP
    cpu_memory.write_memory(memory, cpu.registers[5].value, value, 4)
end

local function pop(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: Instruction)
    local value = cpu_memory.read_memory(memory, cpu.registers[5].value, 4)
    set_operand_value(cpu, memory, instruction.operands[1], value)
    cpu.registers[5].value = cpu.registers[5].value + 4 -- Increment ESP
end

local function call(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: Instruction)
    local offset = get_operand_value(cpu, memory, instruction.operands[1])
    push(cpu, memory, {opcode = 0, size = 0, operands = {{type = "register", value = 8}}}) -- Push EIP
    cpu.ip = cpu.ip + offset
end

local function ret(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: Instruction)
    pop(cpu, memory, {opcode = 0, size = 0, operands = {{type = "register", value = 8}}}) -- Pop EIP
end

local function mul(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local value = get_operand_value(cpu, memory, instruction.operands[1])
    local eax_value = cpu_memory.get_register_value(cpu, 0) -- EAX
    local result = eax_value * value
    cpu_memory.set_register_value(cpu, 0, bit32.band(result, 0xFFFFFFFF)) -- Lower 32 bits to EAX
    cpu_memory.set_register_value(cpu, 2, bit32.rshift(result, 32)) -- Upper 32 bits to EDX
    update_flags(cpu, result, eax_value, value)
end

local function div(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local divisor = get_operand_value(cpu, memory, instruction.operands[1])
    local eax_value = cpu_memory.get_register_value(cpu, 0) -- EAX
    local edx_value = cpu_memory.get_register_value(cpu, 2) -- EDX
    local dividend = bit32.bor(bit32.lshift(edx_value, 32), eax_value)
    local quotient = math.floor(dividend / divisor)
    local remainder = dividend % divisor
    cpu_memory.set_register_value(cpu, 0, quotient) -- Quotient to EAX
    cpu_memory.set_register_value(cpu, 2, remainder) -- Remainder to EDX
end

local function inc(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local value = get_operand_value(cpu, memory, instruction.operands[1])
    local result = value + 1
    set_operand_value(cpu, memory, instruction.operands[1], bit32.band(result, 0xFFFFFFFF))
    update_flags(cpu, result, value, 1)
end

local function dec(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local value = get_operand_value(cpu, memory, instruction.operands[1])
    local result = value - 1
    set_operand_value(cpu, memory, instruction.operands[1], bit32.band(result, 0xFFFFFFFF))
    update_flags(cpu, result, value, 1)
end

local function shl(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local value = get_operand_value(cpu, memory, instruction.operands[1])
    local shift = get_operand_value(cpu, memory, instruction.operands[2])
    local result = bit32.lshift(value, shift)
    set_operand_value(cpu, memory, instruction.operands[1], result)
    update_flags(cpu, result, value, shift)
end

local function shr(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local value = get_operand_value(cpu, memory, instruction.operands[1])
    local shift = get_operand_value(cpu, memory, instruction.operands[2])
    local result = bit32.rshift(value, shift)
    set_operand_value(cpu, memory, instruction.operands[1], result)
    update_flags(cpu, result, value, shift)
end

local function rol(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local value = get_operand_value(cpu, memory, instruction.operands[1])
    local rotate = get_operand_value(cpu, memory, instruction.operands[2])
    local result = bit32.bor(bit32.lshift(value, rotate), bit32.rshift(value, 32 - rotate))
    set_operand_value(cpu, memory, instruction.operands[1], result)
    update_flags(cpu, result, value, rotate)
end

local function ror(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local value = get_operand_value(cpu, memory, instruction.operands[1])
    local rotate = get_operand_value(cpu, memory, instruction.operands[2])
    local result = bit32.bor(bit32.rshift(value, rotate), bit32.lshift(value, 32 - rotate))
    set_operand_value(cpu, memory, instruction.operands[1], result)
    update_flags(cpu, result, value, rotate)
end

local function and_op(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = bit32.band(dest_value, src_value)
    set_operand_value(cpu, memory, dest, result)
    update_flags(cpu, result, src_value, dest_value)
end

local function or_op(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = bit32.bor(dest_value, src_value)
    set_operand_value(cpu, memory, dest, result)
    update_flags(cpu, result, src_value, dest_value)
end

local function xor_op(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = bit32.bxor(dest_value, src_value)
    set_operand_value(cpu, memory, dest, result)
    update_flags(cpu, result, src_value, dest_value)
end

local function cmp(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = dest_value - src_value
    update_flags(cpu, result, src_value, dest_value)
end

local function je(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    if cpu_memory.get_flag(cpu, cpu_memory.FLAGS.ZF) then
        jmp(cpu, memory, instruction)
    end
end

local function jne(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    if not cpu_memory.get_flag(cpu, cpu_memory.FLAGS.ZF) then
        jmp(cpu, memory, instruction)
    end
end

local function jg(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    if not cpu_memory.get_flag(cpu, cpu_memory.FLAGS.ZF) and
       cpu_memory.get_flag(cpu, cpu_memory.FLAGS.SF) == cpu_memory.get_flag(cpu, cpu_memory.FLAGS.OF) then
        jmp(cpu, memory, instruction)
    end
end

local function jl(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    if cpu_memory.get_flag(cpu, cpu_memory.FLAGS.SF) ~= cpu_memory.get_flag(cpu, cpu_memory.FLAGS.OF) then
        jmp(cpu, memory, instruction)
    end
end

local instruction_set = {
    [0x01] = add,
    [0x09] = or_op,
    [0x21] = and_op,
    [0x29] = sub,
    [0x31] = xor_op,
    [0x39] = cmp,
    [0x50] = push,
    [0x58] = pop,
    [0x74] = je,
    [0x75] = jne,
    [0x7C] = jl,
    [0x7F] = jg,
    [0x89] = mov,
    [0x8B] = mov,
    [0xB8] = mov,
    [0xC3] = ret,
    [0xE8] = call,
    [0xE9] = jmp,
    [0xEB] = jmp,
    [0xF7] = {[0] = mul, [1] = div},
    [0xFF] = {[0] = inc, [1] = dec},
    [0xD3] = {[4] = shl, [5] = shr, [0] = rol, [1] = ror},
}

local function execute_instruction(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local opcode = instruction.opcode
    local handler = instruction_set[opcode]
    
    if type(handler) == "function" then
        handler(cpu, memory, instruction)
    elseif type(handler) == "table" then
        local subopcode = instruction.operands[1].value
        local subhandler = handler[subopcode]
        if subhandler then
            subhandler(cpu, memory, instruction)
        else
            error(string.format("Unhandled subopcode 0x%X for opcode 0x%X", subopcode, opcode))
        end
    else
        error(string.format("Unhandled opcode: 0x%X", opcode))
    end
    
    
    cpu.ip = cpu.ip + instruction.size
end

local function print_instruction(instruction: decoder_module.Instruction)
    local opcode_name = ""
    for name, func in pairs(instruction_set) do
        if func == instruction_set[instruction.opcode] then
            opcode_name = name
            break
        end
    end
    
    local operands_str = {}
    for _, operand in ipairs(instruction.operands) do
        if operand.type == "register" then
            table.insert(operands_str, string.format("reg%d", operand.value))
        elseif operand.type == "immediate" then
            table.insert(operands_str, string.format("0x%X", operand.value))
        elseif operand.type == "memory" then
            table.insert(operands_str, string.format("[0x%X]", operand.value))
        end
    end
    
    print(string.format("%s %s", opcode_name, table.concat(operands_str, ", ")))
end

local function check_condition(cpu: cpu_memory.CPU, condition: string): boolean
    local zf = cpu_memory.get_flag(cpu, cpu_memory.FLAGS.ZF)
    local sf = cpu_memory.get_flag(cpu, cpu_memory.FLAGS.SF)
    local of = cpu_memory.get_flag(cpu, cpu_memory.FLAGS.OF)
    
    if condition == "e" or condition == "z" then
        return zf
    elseif condition == "ne" or condition == "nz" then
        return not zf
    elseif condition == "g" then
        return not zf and (sf == of)
    elseif condition == "l" then
        return sf ~= of
    elseif condition == "ge" then
        return sf == of
    elseif condition == "le" then
        return zf or (sf ~= of)
    else
        error("Unknown condition: " .. condition)
    end
end

-- Generic conditional jump function
local function conditional_jump(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction, condition: string)
    if check_condition(cpu, condition) then
        jmp(cpu, memory, instruction)
    end
end

-- Etelehaj!
instruction_set[0x74] = function(cpu, memory, instruction) conditional_jump(cpu, memory, instruction, "e") end  -- JE/JZ
instruction_set[0x75] = function(cpu, memory, instruction) conditional_jump(cpu, memory, instruction, "ne") end -- JNE/JNZ
instruction_set[0x7F] = function(cpu, memory, instruction) conditional_jump(cpu, memory, instruction, "g") end  -- JG
instruction_set[0x7C] = function(cpu, memory, instruction) conditional_jump(cpu, memory, instruction, "l") end  -- JL
instruction_set[0x7D] = function(cpu, memory, instruction) conditional_jump(cpu, memory, instruction, "ge") end -- JGE
instruction_set[0x7E] = function(cpu, memory, instruction) conditional_jump(cpu, memory, instruction, "le") end -- JLE

return {
    execute_instruction = execute_instruction,
    print_instruction = print_instruction,
    instruction_set = instruction_set
}