; ********************************************************************************
; MTRX2700 Lab 2
; Task 1 Part 1: "Serial Output'
; GROUP:
; MEMBERS:
; DESCRIPTION: 
; MODIFIED:
; ********************************************************************************

; export symbols
            XDEF                Entry, _Startup ; export 'Entry' symbol
            ABSENTRY            Entry           ; for absolute assembly: mark this as application entry point

; Include derivative-specific definitions 
		INCLUDE 'derivative.inc' 

;**************************************************************
;*                 Interrupt Vectors                          *
;**************************************************************
                ORG             $FFFE
                DC.W            Entry           ; Reset Vector
                
ROMStart        EQU             $4000           

; variable/data section
                ORG             RAMStart

TDRE_bitmask    FCB             $80
str1            FCB             "first string"
str2            FCB             "second thingy"

; code section
                ORG             ROMStart

Entry:
_Startup:
                LDS             #RAMEnd+1       ; initialize the stack pointer
                
                ; configure the serial communications interface
config_sci      SEI                             ; disable all interrupts
                
                ; TODO: find appropriate baud rate value
                MOVB            #$ff,SCI0BDL    ; set the baud rate low byte
                MOVB            #$ff,SCI0BDH    ; set the baud rate higher bits
                
                ; now set word length and wake up, and parity configuration
                ; TODO: figure out if this is correct in the lab
                MOVB            #$0E,SCI0CR1

                ; complete SCI config by writing to the SCI control register 2
                ; configures (... stuff here)
                ; TODO: figure out if this is correct, I think this one is
                ; (this enables only the transmitter bit, nothing else)
                MOVB            #$08,SCI0CR2

                CLI                             ; enable interrupts

                LDX             #0
                
                ; write to the SCI in a loop
LOOP_WRITE_SCI:
                LDAA            SCI0SR1         ; poll the SCI status register
                ANDA            TDRE_bitmask    ; isolate the TDRE bit
                BEQ             LOOP_WRITE_SCI  ; if TDRE is 0, keep looping
                MOVB            #$41,SCI0DRL    ; write an A to the SCI
                INX                             ; count how many times we've done this (debugging)
                JSR             delay_1_sec     ; delay for about a second
                BRA             LOOP_WRITE_SCI
                
; ********************************************************************************
; SUBROUTINE: delay_1_sec
; ARGS: None
; waits exactly one second, using an outer and inner (nested) loop 
; with predefined constants - see logbook for derivation
; (also uses a secondary smaller loop for fine tuning)
; ********************************************************************************
delay_1_sec:
                PSHX                            ; push X to the stack, in case the  caller is using
                PSHY                            ; same thing for Y
                LDX             #1000           ; load decrement counter (constant C1) in x
delay_1_sec_L:  
                LDY             #5998           ; load decrement counter (constant C2) in y
delay_1_sec_L2: 
                DEY                             ; decrement Y every inner loop cycle
                BNE             delay_1_sec_L2  ; if Y isn't 0, branch to the inner loop
                DEX                             ; decrement X every outer loop cycle
                BNE             delay_1_sec_L   ; if X isn't 0, branch to the outer loop
            
; this gets pretty close, but not quite: so run another small loop to make up for it
                LDX             #996            ; constant C3
delay_1_sec_L3: 
                DEX                             ; decrement X
                BNE             delay_1_sec_L3  ; if X isn't zero, branch to loop
                             
; before returning, pop original x and y for the caller to use off the stack
                PULY                            ; pop Y first (correct reverse order)
                PULX                            ; then pop X
                RTS                             ; return
