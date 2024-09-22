--!native
--!strict
--!optimize 2

local cpu_memory = require("cpu_and_memory")

export type Operand = {
    type: string, -- "register", "immediate", "memory"
    value: number
}

export type Instruction = {
    opcode: number,
    operands: {Operand},
    size: number
}

local function decode_modrm(cpu: cpu_memory.CPU, memory: cpu_memory.Memory): (number, number, number)
    local modrm = cpu_memory.read_memory(memory, cpu.ip, 1)
    cpu.ip += 1
    local mod = bit32.rshift(modrm, 6)
    local reg = bit32.band(bit32.rshift(modrm, 3), 0x7)
    local rm = bit32.band(modrm, 0x7)
    return mod, reg, rm
end

local function decode_sib(cpu: cpu_memory.CPU, memory: cpu_memory.Memory): (number, number, number)
    local sib = cpu_memory.read_memory(memory, cpu.ip, 1)
    cpu.ip += 1
    local scale = bit32.rshift(sib, 6)
    local index = bit32.band(bit32.rshift(sib, 3), 0x7)
    local base = bit32.band(sib, 0x7)
    return scale, index, base
end

local function decode_operand(cpu: cpu_memory.CPU, memory: cpu_memory.Memory, mod: number, rm: number): Operand
    if mod == 3 then
        return {type = "register", value = rm}
    elseif mod == 0 and rm == 5 then
        local disp32 = cpu_memory.read_memory(memory, cpu.ip, 4)
        cpu.ip += 4
        return {type = "memory", value = disp32}
    else
        local addr = 0
        if rm == 4 then
            local scale, index, base = decode_sib(cpu, memory)
            addr = cpu_memory.get_register_value(cpu, base)
            if index ~= 4 then
                addr += cpu_memory.get_register_value(cpu, index) * (2 ^ scale)
            end
        else
            addr = cpu_memory.get_register_value(cpu, rm)
        end
        
        if mod == 1 then
            local disp8 = cpu_memory.read_memory(memory, cpu.ip, 1)
            cpu.ip += 1
            addr += bit32.arshift(bit32.lshift(disp8, 24), 24) -- Sign extend
        elseif mod == 2 then
            local disp32 = cpu_memory.read_memory(memory, cpu.ip, 4)
            cpu.ip += 4
            addr += disp32
        end
        
        return {type = "memory", value = addr}
    end
end

local function decode_instruction(cpu: cpu_memory.CPU, memory: cpu_memory.Memory): Instruction
    local opcode = cpu_memory.read_memory(memory, cpu.ip, 1)
    cpu.ip += 1
    local instruction: Instruction = {opcode = opcode, operands = {}, size = 1}

    if opcode == 0xE9 then -- JMP rel32
        local rel32 = cpu_memory.read_memory(memory, cpu.ip, 4)
        cpu.ip += 4
        instruction.operands[1] = {type = "immediate", value = rel32}
        instruction.size += 4
    elseif opcode == 0xEB then -- JMP rel8
        local rel8 = cpu_memory.read_memory(memory, cpu.ip, 1)
        cpu.ip += 1
        instruction.operands[1] = {type = "immediate", value = rel8}
        instruction.size += 1
    elseif opcode >= 0x50 and opcode <= 0x57 then -- PUSH r32
        local reg = opcode - 0x50
        instruction.operands[1] = {type = "register", value = reg}
    elseif opcode >= 0x58 and opcode <= 0x5F then -- POP r32
        local reg = opcode - 0x58
        instruction.operands[1] = {type = "register", value = reg}
    elseif opcode == 0x8B then -- MOV r32, r/m32
        local mod, reg, rm = decode_modrm(cpu, memory)
        instruction.operands[1] = {type = "register", value = reg}
        instruction.operands[2] = decode_operand(cpu, memory, mod, rm)
        instruction.size += 1
    elseif opcode == 0x89 then -- MOV r/m32, r32
        local mod, reg, rm = decode_modrm(cpu, memory)
        instruction.operands[1] = decode_operand(cpu, memory, mod, rm)
        instruction.operands[2] = {type = "register", value = reg}
        instruction.size += 1
    elseif opcode >= 0xB8 and opcode <= 0xBF then -- MOV r32, imm32
        local reg = opcode - 0xB8
        local imm32 = cpu_memory.read_memory(memory, cpu.ip, 4)
        cpu.ip += 4
        instruction.operands[1] = {type = "register", value = reg}
        instruction.operands[2] = {type = "immediate", value = imm32}
        instruction.size += 4
    elseif opcode == 0x01 then -- ADD r/m32, r32
        local mod, reg, rm = decode_modrm(cpu, memory)
        instruction.operands[1] = decode_operand(cpu, memory, mod, rm)
        instruction.operands[2] = {type = "register", value = reg}
        instruction.size += 1
    elseif opcode == 0x29 then -- SUB r/m32, r32
        local mod, reg, rm = decode_modrm(cpu, memory)
        instruction.operands[1] = decode_operand(cpu, memory, mod, rm)
        instruction.operands[2] = {type = "register", value = reg}
        instruction.size += 1
    elseif opcode == 0x21 then -- AND r/m32, r32
        local mod, reg, rm = decode_modrm(cpu, memory)
        instruction.operands[1] = decode_operand(cpu, memory, mod, rm)
        instruction.operands[2] = {type = "register", value = reg}
        instruction.size += 1
    elseif opcode == 0x09 then -- OR r/m32, r32
        local mod, reg, rm = decode_modrm(cpu, memory)
        instruction.operands[1] = decode_operand(cpu, memory, mod, rm)
        instruction.operands[2] = {type = "register", value = reg}
        instruction.size += 1
    elseif opcode == 0x31 then -- XOR r/m32, r32
        local mod, reg, rm = decode_modrm(cpu, memory)
        instruction.operands[1] = decode_operand(cpu, memory, mod, rm)
        instruction.operands[2] = {type = "register", value = reg}
        instruction.size += 1
    elseif opcode == 0xE8 then -- CALL rel32
        local rel32 = cpu_memory.read_memory(memory, cpu.ip, 4)
        cpu.ip += 4
        instruction.operands[1] = {type = "immediate", value = rel32}
        instruction.size += 4
    elseif opcode == 0xC3 then -- RET
        -- No operands needed for RET
    elseif opcode == 0x74 then -- JE/JZ rel8
        local rel8 = cpu_memory.read_memory(memory, cpu.ip, 1)
        cpu.ip += 1
        instruction.operands[1] = {type = "immediate", value = rel8}
        instruction.size += 1
    elseif opcode == 0x75 then -- JNE/JNZ rel8
        local rel8 = cpu_memory.read_memory(memory, cpu.ip, 1)
        cpu.ip += 1
        instruction.operands[1] = {type = "immediate", value = rel8}
        instruction.size += 1
    elseif opcode == 0x7F then -- JG rel8
        local rel8 = cpu_memory.read_memory(memory, cpu.ip, 1)
        cpu.ip += 1
        instruction.operands[1] = {type = "immediate", value = rel8}
        instruction.size += 1
    elseif opcode == 0x7C then -- JL rel8
        local rel8 = cpu_memory.read_memory(memory, cpu.ip, 1)
        cpu.ip += 1
        instruction.operands[1] = {type = "immediate", value = rel8}
        instruction.size += 1
    elseif opcode == 0xF7 then -- MUL/DIV/IMUL/IDIV r/m32
        local mod, reg, rm = decode_modrm(cpu, memory)
        instruction.operands[1] = decode_operand(cpu, memory, mod, rm)
        instruction.size += 1
    elseif opcode == 0xFF then -- INC/DEC r/m32
        local mod, reg, rm = decode_modrm(cpu, memory)
        instruction.operands[1] = decode_operand(cpu, memory, mod, rm)
        instruction.size += 1
    elseif opcode == 0xD3 then -- SHL/SHR/SAL/SAR/ROL/ROR r/m32, CL
        local mod, reg, rm = decode_modrm(cpu, memory)
        instruction.operands[1] = decode_operand(cpu, memory, mod, rm)
        instruction.operands[2] = {type = "register", value = 1} -- CL register
        instruction.size += 1
    elseif opcode == 0x0F then -- Two-byte opcode
        local second_opcode = cpu_memory.read_memory(memory, cpu.ip, 1)
        cpu.ip += 1
        instruction.opcode = bit32.lshift(opcode, 8) + second_opcode
        instruction.size += 1

        if second_opcode == 0xAF then -- IMUL r32, r/m32
            local mod, reg, rm = decode_modrm(cpu, memory)
            instruction.operands[1] = {type = "register", value = reg}
            instruction.operands[2] = decode_operand(cpu, memory, mod, rm)
            instruction.size += 1
        elseif second_opcode == 0xBE then -- MOVSX r32, r/m8
            local mod, reg, rm = decode_modrm(cpu, memory)
            instruction.operands[1] = {type = "register", value = reg}
            instruction.operands[2] = decode_operand(cpu, memory, mod, rm)
            instruction.size += 1
        elseif second_opcode == 0xBF then -- MOVSX r32, r/m16
            local mod, reg, rm = decode_modrm(cpu, memory)
            instruction.operands[1] = {type = "register", value = reg}
            instruction.operands[2] = decode_operand(cpu, memory, mod, rm)
            instruction.size += 1
        else
            error(string.format("Unimplemented two-byte opcode: 0x0F%02X", second_opcode))
        end
    else
        error(string.format("Unimplemented opcode: 0x%02X", opcode))
    end
    
    return instruction
end

return {
    decode_instruction = decode_instruction
}