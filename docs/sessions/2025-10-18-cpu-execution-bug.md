# CPU Execution Bug Investigation (2025-10-18)

## Critical Finding

**PC=$A319 should execute LDA #$5A but executes BRK/ORA ($nn,X) instead**

## Evidence

- ROM bytes at $A319: Verified correct (presumably $A9 $5A for LDA #$5A)
- Executed opcode: $00 (BRK) or $01 (ORA ($nn,X) indexed indirect)
- Conclusion: CPU is reading from wrong address or wrong memory

## Possible Root Causes

### 1. PC Calculation Wrong
- PC shown as $A319 but actually fetching from different address
- Off-by-one in PC increment?
- PC wrapping incorrectly?

### 2. Bank Mapping Wrong (MMC3)
- $A319 is in CPU address range $A000-$BFFF
- MMC3 maps this to PRG bank (R7 register)
- Could be reading from wrong PRG bank

### 3. Memory Read Path Broken
- CPU fetch goes through wrong path
- Bus read returning wrong data
- Open bus issue?

### 4. ROM Loading Issue
- ROM bytes loaded to wrong offset
- Bank boundaries wrong
- iNES header parsing error?

## Investigation Steps

1. **Verify ROM bytes directly:**
   - Read ROM file at correct offset
   - Confirm $A9 $5A exists at expected location

2. **Trace CPU fetch:**
   - Log CPU read for instruction fetch
   - Verify address requested = $A319
   - Verify data returned

3. **Check bank mapping:**
   - What PRG bank does $A000 map to?
   - Is R7 register set correctly?
   - Calculate expected ROM offset

4. **Test with simple case:**
   - Set PC to known ROM location
   - Verify opcode fetch matches ROM bytes

## Next Actions

- [ ] Instrument CPU instruction fetch
- [ ] Log: PC, requested address, returned byte
- [ ] Verify bank calculation
- [ ] Check if PC display matches actual PC used for fetch
