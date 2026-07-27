# LSK M6T912F Floppy Duplicator KOP05B/SK

TERRA computer systems (c) 1993

## Connectors/Test-points

- B5 
- B53/B55/B54 GND/K54-13/5V/K54-14/GND
- J1 
- J2 
- J3 
- J7/B7 
- J8/B8 
- J9/B1 
- J10/B2 
- J11 
- J12 
- J13 
- J14 
- J51/B51 
- J101/B101 nc/A14 EEPROM/5V (with a 64kb EPROM switch to alternative bank)
- K1 Floppy Connector U1/U2?
- K2 Floppy Connector U?
- K3 Floppy Connector U1/U2?
- K4 
- K51 LCD
- K52 4 buttons and beeper
- K53 
- K54 1:/2:/3:SIO DCDB/4:SIO DCDA/5:SIO RTSB/6:SIO RTSA/7:SIO CTSB/8:SIO CTSA/9:R2in/10:R1in/11:T1out/12:T2out/13:B53/14:B54
- MB1 GND
- MB2 U1 /RDD Raw serial bit stream from disk drive
- MB3 GND
- MB4 U3 /RDD Raw serial bit stream from disk drive
- MB5 HLDA at U7 (µPD8237A DMA Controller)
- MB6 GND
- MB7 +5V


## Components:

- U1-U4: SMC FDC37C65C 2.88MB Floppy Disk Controller
- U5: GAL20V8B 15LP
- U6: SN74LS38N — Quad 2-input NAND, open-collector
- U7: NEC D8237A DMA Controller (under sticker)
- U8: 74HCT373N — Octal transparent D-latch, 3-state
- U9: MC74HCT04AN — Hex inverter
- U10: MC74HCT04AN — Hex inverter
- U11: CD74HCT02E — Quad 2-input NOR gate
- U12: 74HCT241N — Octal buffer/line driver, 3-state
- U13: SN74S112N — Dual JK flip-flop, edge-triggered
- U14: SN74S112N — Dual JK flip-flop, edge-triggered
- U15: SN74F08 — Quad 2-input AND gate
- U16: MC74F04N — Hex inverter
- U17: MC74LS93N — 4-bit binary ripple counter
- U18: CD74HCT02E — Quad 2-input NOR gate
- U19: 74HCT157N — Quad 2:1 data multiplexer
- U20: 48MHz Quarzoszillator
- U21: 32MHz Quarzoszillator
- U22: SN74F08N — Quad 2-input AND gate
- U47: SN74ALS245AN — Octal bus transceiver, 3-state
- U51: Z80 CPU
- U52: 74HCT157N — Quad 2:1 data multiplexer
- U53: 74HCT157N — Quad 2:1 data multiplexer
- U54: 74HCT157N — Quad 2:1 data multiplexer
- U55: SN74HCT74N — Dual D flip-flop, edge-triggered
- U56: MC74HCT138AN — 3-to-8 line decoder/demultiplexer
- U57: 32KB EPROM
- U58: MC74HCT245AN — Octal bus transceiver, 3-state
- U59: MC74HCT138AN — 3-to-8 line decoder/demultiplexer
- U60: MC74HCT138AN — 3-to-8 line decoder/demultiplexer
- U61: SN74HCT74N — Dual D flip-flop, edge-triggered
- U62: SN74HCT74N — Dual D flip-flop, edge-triggered
- U65: 74HCT373N — Octal transparent D-latch, 3-state
- U66: 74HCT373N — Octal transparent D-latch, 3-state
- U67: SN74HCT125N — Quad 3-state bus buffer
- U68: PALCE20V8H-25PC/4
- U69: NEC µPD71055 Parallel Interface Unit
- U70: NEC D8253C Programmable Interval Timer
- U71: Z80 SIO/0
- U72: CD74HCT02E — Quad 2-input NOR gate
- U77: SIMMs (with AS4C14400 1M×4 RAM)
- U78: SIMMs (with AS4C14400 1M×4 RAM)
- U79: MC74HCT14AN — Hex Schmitt-trigger inverter
- U83: 74HCT373N — Octal transparent D-latch, 3-state
- U84: CD74HCT02E — Quad 2-input NOR gate
- U85: 74HCT373N — Octal transparent D-latch, 3-state
- U86: CAT24C02 2-Kb I2C CMOS Serial EEPROM
- U87: MC74HCT245AN — Octal bus transceiver, 3-state
- U88: MC74HCT04AN — Hex inverter
- U101: Microchip TC232CPE Dual RS-232 Transmitter/Receiver And Power Supply
