--!native
--!strict
--!optimize 2

export type Register = {
    name: string,
    size: number,
    value: number
}

export type CPU = {
    registers: {Register},
    flags: number,
    ip: number
}

export type Memory = {
    data: {number},
    size: number
}

export type FLAGS = {
    CF: number,
    ZF: number,
    SF: number,
    OF: number
}

local FLAGS: FLAGS = {
    CF = 0, -- Carry Flag
    ZF = 6, -- Zero Flag
    SF = 7, -- Sign Flag
    OF = 11 -- Overflow Flag
}

local function create_register(name: string, size: number): Register
    return {name = name, size = size, value = 0}
end

local function create_cpu(): CPU
    local cpu: CPU = {
        registers = {},
        flags = 0,
        ip = 0
    }

    local register_names = {"eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi"}
    for _, name in ipairs(register_names) do
        table.insert(cpu.registers, create_register(name, 32))
    end

    return cpu
end

local function get_register_value(cpu: CPU, reg_index: number): number
    return cpu.registers[reg_index + 1].value
end

local function set_register_value(cpu: CPU, reg_index: number, value: number)
    cpu.registers[reg_index + 1].value = value
end

local function get_flag(cpu: CPU, flag_bit: number): boolean
    return bit32.band(cpu.flags, bit32.lshift(1, flag_bit)) ~= 0
end

local function set_flag(cpu: CPU, flag_bit: number, value: boolean)
    if value then
        cpu.flags = bit32.bor(cpu.flags, bit32.lshift(1, flag_bit))
    else
        cpu.flags = bit32.band(cpu.flags, bit32.bnot(bit32.lshift(1, flag_bit)))
    end
end

local function create_memory(size: number): Memory
    return {
        data = table.create(size, 0),
        size = size
    }
end

local function read_memory(memory: Memory, address: number, size: number): number
    assert(address >= 0 and address + size <= memory.size, "Memory access out of bounds")
    local value = 0
    for i = 0, size - 1 do
        value = bit32.bor(value, bit32.lshift(memory.data[address + i + 1], i * 8))
    end
    return value
end

local function write_memory(memory: Memory, address: number, value: number, size: number)
    assert(address >= 0 and address + size <= memory.size, "Memory access out of bounds")
    for i = 0, size - 1 do
        memory.data[address + i + 1] = bit32.band(bit32.rshift(value, i * 8), 0xFF)
    end
end

return {
    create_cpu = create_cpu,
    get_register_value = get_register_value,
    set_register_value = set_register_value,
    get_flag = get_flag,
    set_flag = set_flag,
    create_memory = create_memory,
    read_memory = read_memory,
    write_memory = write_memory,
    FLAGS = FLAGS
}