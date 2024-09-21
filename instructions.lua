--!native
--!strict
--!optimize 2

local cpu_memory = require("cpu_and_memory")
local decoder_module = require("decoder")

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
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.ZF, result == 0) -- Zero Flag
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.SF, bit32.btest(result, 0x80000000)) -- Sign Flag
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.CF, result < 0 or result > 0xFFFFFFFF) -- Carry Flag
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.OF, 
        (bit32.bxor(bit32.rshift(src, 31), bit32.rshift(dest, 31)) == 0) and
        (bit32.bxor(bit32.rshift(result, 31), bit32.rshift(src, 31)) == 1)
    ) -- Overflow Flag
end

local function mov(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local value = get_operand_value(cpu, memory, src)
    set_operand_value(cpu, memory, dest, value)
end

local function add(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = dest_value + src_value
    set_operand_value(cpu, memory, dest, bit32.band(result, 0xFFFFFFFF))
    update_flags(cpu, result, src_value, dest_value)
end

local function sub(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = dest_value - src_value
    set_operand_value(cpu, memory, dest, bit32.band(result, 0xFFFFFFFF))
    update_flags(cpu, result, src_value, dest_value)
end

local function and_op(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = bit32.band(dest_value, src_value)
    set_operand_value(cpu, memory, dest, result)
    update_flags(cpu, result, src_value, dest_value)
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.CF, false)
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.OF, false)
end

local function or_op(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = bit32.bor(dest_value, src_value)
    set_operand_value(cpu, memory, dest, result)
    update_flags(cpu, result, src_value, dest_value)
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.CF, false)
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.OF, false)
end

local function xor_op(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local dest, src = instruction.operands[1], instruction.operands[2]
    local dest_value = get_operand_value(cpu, memory, dest)
    local src_value = get_operand_value(cpu, memory, src)
    local result = bit32.bxor(dest_value, src_value)
    set_operand_value(cpu, memory, dest, result)
    update_flags(cpu, result, src_value, dest_value)
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.CF, false)
    cpu_memory.set_flag(cpu, cpu_memory.FLAGS.OF, false)
end

local function push(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local value = get_operand_value(cpu, memory, instruction.operands[1])
    cpu_memory.set_register_value(cpu, 7, cpu_memory.get_register_value(cpu, 7) - 4) -- Decrement ESP
    cpu_memory.write_memory(memory, cpu_memory.get_register_value(cpu, 7), value, 4)
end

local function pop(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local value = cpu_memory.read_memory(memory, cpu_memory.get_register_value(cpu, 7), 4)
    set_operand_value(cpu, memory, instruction.operands[1], value)
    cpu_memory.set_register_value(cpu, 7, cpu_memory.get_register_value(cpu, 7) + 4) -- Increment ESP
end

local function jmp(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local offset = get_operand_value(cpu, memory, instruction.operands[1])
    if instruction.size == 2 then -- JMP rel8
        offset = bit32.arshift(bit32.lshift(offset, 24), 24) -- Sign extend 8-bit to 32-bit
    end
    cpu.ip += offset
end

local instruction_handlers = {
    [0x8B] = mov,
    [0x89] = mov,
    [0xB8] = mov,
    [0x01] = add,
    [0x29] = sub,
    [0x21] = and_op,
    [0x09] = or_op,
    [0x31] = xor_op,
    [0x50] = push,
    [0x51] = push,
    [0x52] = push,
    [0x53] = push,
    [0x54] = push,
    [0x55] = push,
    [0x56] = push,
    [0x57] = push,
    [0x58] = pop,
    [0x59] = pop,
    [0x5A] = pop,
    [0x5B] = pop,
    [0x5C] = pop,
    [0x5D] = pop,
    [0x5E] = pop,
    [0x5F] = pop,
    [0xE9] = jmp, -- JMP rel32
    [0xEB] = jmp, -- JMP rel8
}

local function execute_instruction(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, instruction: decoder_module.Instruction)
    local handler = instruction_handlers[instruction.opcode]
    if handler then
        handler(cpu, memory, instruction)
    else
        error(string.format("Unimplemented instruction: 0x%02X", instruction.opcode))
    end
    
    if instruction.opcode ~= 0xE9 and instruction.opcode ~= 0xEB then
        cpu.ip += instruction.size
    end
end

return {
    execute_instruction = execute_instruction
}