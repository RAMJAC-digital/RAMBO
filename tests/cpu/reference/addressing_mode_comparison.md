# Addressing Mode Timing Comparison

**Purpose:** Understand why immediate, zero_page, and absolute modes have correct timing, while absolute,X has +1 cycle deviation.

---

## Working Modes (No Timing Issues)

### Immediate Mode - 2 Cycles ✅

**Hardware:**
| Cycle | Action |
|-------|--------|
| 1 | Fetch opcode |
| 2 | **Read operand from PC + Execute** |

**Our Implementation:**
```zig
// In tickCpu():
if (needs_addressing) {
    self.cpu.state = .fetch_operand_low;
} else {
    self.cpu.state = .execute;  // ← Goes straight to execute
}

// In execute state:
.immediate => self.busRead(self.cpu.pc),  // ← Reads operand inline
```

**Why It Works:** No addressing state. Execute reads operand inline. **Read + Execute = Same Cycle**

---

### Zero Page Mode - 3 Cycles ✅

**Hardware:**
| Cycle | Action |
|-------|--------|
| 1 | Fetch opcode |
| 2 | Fetch zero page address |
| 3 | **Read from ZP address + Execute** |

**Our Implementation:**
```zig
// Addressing state (ic=0):
0 => self.fetchOperandLow(),  // Stores ZP address

// addressing_done when ic >= 1

// Execute state:
.zero_page => self.busRead(@as(u16, self.cpu.operand_low)),  // ← Reads operand
```

**Analysis:**
- Addressing: 1 cycle (fetch ZP address)
- Execute: 1 cycle (read from ZP + execute)
- Total: **3 cycles** ✅

**Why It Works:** Execute state reads the operand. Total cycles = fetch(1) + address(1) + execute(1) = 3

---

### Absolute Mode - 4 Cycles ✅

**Hardware:**
| Cycle | Action |
|-------|--------|
| 1 | Fetch opcode |
| 2 | Fetch low byte |
| 3 | Fetch high byte |
| 4 | **Read from absolute address + Execute** |

**Our Implementation:**
```zig
// Addressing state:
0 => self.fetchAbsLow(),
1 => self.fetchAbsHigh(),

// addressing_done when ic >= 2

// Execute state:
.absolute => blk: {
    const addr = (@as(u16, self.cpu.operand_high) << 8) | self.cpu.operand_low;
    break :blk self.busRead(addr);  // ← Reads operand
},
```

**Analysis:**
- Addressing: 2 cycles (fetch low + high)
- Execute: 1 cycle (read from address + execute)
- Total: **4 cycles** ✅

**Why It Works:** Execute state reads the operand. Total = fetch(1) + addressing(2) + execute(1) = 4

---

## Broken Mode (Timing Deviation)

### Absolute,X Mode (No Page Cross) - Should be 4, Actually 5 ❌

**Hardware (4 cycles):**
| Cycle | Action |
|-------|--------|
| 1 | Fetch opcode |
| 2 | Fetch low byte |
| 3 | Fetch high byte, add X |
| 4 | **Read from base+X + Execute** (no page cross = address already correct) |

**Our Implementation (5 cycles):**
```zig
// Addressing state:
0 => self.fetchAbsLow(),
1 => self.fetchAbsHigh(),
2 => self.calcAbsoluteX(),  // ← Reads dummy value into temp_value
3 => self.fixHighByte(),    // ← Does nothing (no page cross)

// addressing_done when ic >= 3 (page not crossed)

// Execute state (happens in cycle 5!):
.absolute_x => if (self.cpu.page_crossed)
    self.busRead(self.cpu.effective_address)
else
    self.cpu.temp_value,  // ← Uses value from cycle 3
```

**Analysis:**
- Cycle 1: fetch opcode
- Cycle 2: fetchAbsLow
- Cycle 3: fetchAbsHigh
- Cycle 4: calcAbsoluteX (reads value, stores in temp_value)
- Cycle 5: Execute (uses temp_value from cycle 4)

**THE PROBLEM:** Cycle 4 already read the operand, but cycle 5 does the execution. Hardware combines these.

---

### Absolute,X Mode (Page Cross) - Should be 5, Actually 6 ❌

**Hardware (5 cycles):**
| Cycle | Action |
|-------|--------|
| 1 | Fetch opcode |
| 2 | Fetch low byte |
| 3 | Fetch high byte, add X |
| 4 | Dummy read at wrong address |
| 5 | **Read from correct address + Execute** |

**Our Implementation (6 cycles):**
```zig
// Addressing state:
0 => self.fetchAbsLow(),
1 => self.fetchAbsHigh(),
2 => self.calcAbsoluteX(),     // ← Dummy read at wrong address
3 => self.fixHighByte(),        // ← Dummy read at correct address (!)
4 => addressing_done (ic >= 4)

// Execute state (cycle 6!):
.absolute_x => self.busRead(self.cpu.effective_address),  // ← THIRD read!
```

**THE PROBLEM:**
- Cycle 4: calcAbsoluteX does dummy read at wrong address
- Cycle 5: fixHighByte does dummy read at CORRECT address (but discards it!)
- Cycle 6: Execute reads AGAIN at correct address

**Hardware only reads twice (wrong address, then correct). We read THREE times!**

---

## Root Cause Analysis

### Pattern in Working Modes

All working modes share this pattern:
1. Addressing state calculates/fetches the address
2. **Execute state reads the operand value**
3. Read + Execute happen in same cycle (tick)

Total cycles = Opcode fetch + Addressing + Execute

### Pattern in Broken Mode

Absolute,X mode breaks the pattern:
1. Addressing state does BOTH:
   - Calculates address
   - **Reads the operand value** (into temp_value)
2. Execute state **uses the pre-read value**
3. But addressing and execute are separate ticks!

Total cycles = Opcode fetch + Addressing (with operand read) + Execute (using cached value)
This adds +1 cycle!

---

## The Solution

### Option 1: Make Execute Read the Operand (Like Other Modes)

**Change addressing state:**
- calcAbsoluteX: Only does dummy read, doesn't use the value
- fixHighByte: Only does dummy read (if page crossed)
- **Don't store operand in temp_value**

**Change execute state:**
- Always reads from effective_address
- This read + execute happen in same cycle

**Problem:** Adds bus reads. Not optimal.

### Option 2: Execute in Same Tick as Final Addressing

**Enable fallthrough:**
- When addressing_done, don't return
- Fall through to execute state in same tick

**Problem:** Breaks modes that need separate execute cycle (like RMW?). Need to make it conditional.

### Option 3: Inline Execute in Final Addressing Microstep

**In fixHighByte (or calcAbsoluteX when no page cross):**
- Read the operand value
- Call the opcode function
- Apply the result
- Set state to fetch_opcode

**Problem:** Breaks separation of concerns. Addressing knows about execution.

---

## Recommended Approach: Option 2 (Conditional Fallthrough)

**Strategy:**
1. Identify which instruction types can safely execute in same tick as addressing
   - Read instructions (LDA, ADC, CMP, etc.): YES
   - Write instructions (STA, STX, etc.): YES
   - RMW instructions (INC, ASL, etc.): NO (need separate cycles)
2. Make addressing_done trigger execute state
3. Make execute state conditional fallthrough based on instruction type

**Implementation:**
```zig
if (addressing_done) {
    self.cpu.state = .execute;
    // For non-RMW instructions, fall through to execute
    if (!entry.is_rmw) {
        // Continue to execute state (don't return)
    } else {
        return;  // RMW needs separate cycle
    }
}
```

This preserves correct timing for RMW while fixing read/write instruction timing.
