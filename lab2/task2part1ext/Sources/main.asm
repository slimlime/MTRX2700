; ********************************************************************************
; MTRX2700 Lab 2
; Task 2 Part 1: "Timer System" Extension
; GROUP: 7
; MEMBERS: Xinzan Guo, David Rapisarda, Thomas T. Cooper, Hughson Xu
; DESCRIPTION: Generates a PWM signal, where both the period and the duty cycle
;               can be adjusted using the serial communications interface. The
;               'Enter' key switches between adjusting the period and duty cycle,
;               and the 'w' and 's' keys increase and decrease the selected value.
; MODIFIED: 10:00 13/04/2016
;               (added more detailed header information)
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
; ISR config - timer 4:
                ORG             $FFE6
                DC.W            isr_timer
; SCI1 RIE:
                ORG             $FFD4
                DC.W            isr_sci_receive

ROMStart        EQU             $4000

TDRE_bitmask    EQU             $80
PERIOD_DEL      EQU             750
DC_DEL          EQU             1

; some ASCII references:
ASCII_w         EQU             $77
ASCII_s         EQU             $73
ASCII_CR        EQU             $0D

; VARIABLES:
                ORG             RAMStart

; string displayed in terminal for adjusting the period:
period_str      FCB             "adjust period (w/s for +/- 1 ms)",$00

; string displayed in terminal for adjusting the duty cycle:
dc_str          FCB             "adjust duty cycle (w/s for +/- 1 ms)",$00

; the PWM period, in cyles * 32 (after prescaling)
PERIOD          FDB             20000

; the 8-bit representation of the duty cycle - 0: 0%, 255: 100%
DUTY_CYCLE_8    FCB             127

; 0 = output signal is currently LOW
; 1 = output signal is currently HIGH
CYCLE_STATE     FCB             $01

; store the prescaled cycles we have to jump
; start with a square wave (so high time = low time)
CYCLES_HIGH     FDB             10000
CYCLES_LOW      FDB             10000

; store what we're adjusting - 0: adjusting period, 1: adjusting duty cycle
ADJUST_STATE    FCB             $00 

; code section
                ORG             ROMStart

Entry:
_Startup:
                LDS             #RAMEnd+1       ; initialize the stack pointer

                SEI                             ; disable all interrupts

; configure the serial communications interface:
                MOVB            #$00,SCI1BDH    ; baud rate higher bytes
                MOVB            #$9C,SCI1BDL    ; baud rate lower bytes (156)
                MOVB            #$00,SCI1CR1    ; M = 0, WAKE = 0
                MOVB            #$2C,SCI1CR2    ; use receive interrupts
                
; configure the timer system registers:
                MOVB            #$00,TCTL1      ; set up output to toggle
                MOVB            #$10,TIOS       ; select channel 4 for output compare
                MOVB            #$80,TSCR1      ; enable timers
                MOVB            #$05,TSCR2      ; prescaler div 16
                BSET            TIE,#$10        ; enable timer interrupt 4
                
                ; NOT SURE IF THIS IS NECESSARY - check on the actual board
                MOVB            #$FF,DDRT       ; configure port T as output

                CLI                             ; re-enable all interrupts
                ; configure DIP switches ports:
                MOVB            #$00,DDRH       ; configure DIP switches as inputs

; configure SCI RIE interrupt as highest priority
                MOVB            #$D4,HPRIO

; loop forever - keep polling the DIP switches for the duty cycle
mainLoop:       BRA             mainLoop

; ******************************************************************************** 
; SUBROUTINE: compute_duty_cycle
; ARGS: B: the duty cycle, from 0-255
; computes the number of cycles to wait during the HIGH and the LOW parts of 
; the period (stores it in memory at CYCLES_HIGH and CYCLES_LOW)
; ********************************************************************************
compute_duty_cycle:
                PSHA                            ; push A to stack in case it's in use
                LDAA            #0              ; load 0 into A
                LDY             PERIOD          ; load the period into Y
                EMUL                            ; extended multiply D and Y
                LDX             #255            ; load 255 into X
                EDIV                            ; extended divide Y:D by X
                STY             CYCLES_HIGH     ; store the HIGH result
                LDD             PERIOD          ; load the period into D
                SUBD            CYCLES_HIGH     ; subtract the HIGH result to obtain LOW
                STD             CYCLES_LOW      ; store the LOW result
                PULA                            ; pull A back from the stack
                RTS                             ; return
                
; ******************************************************************************** 
; SUBROUTINE: write_newline_sci
; ARGS: None
; writes \r\n (carriage return then a new line character) to the terminal
; ********************************************************************************
write_newline_sci:
                PSHB                            ; put B on the stack in case it's in use
                LDAB            #$0D            ; load B with ASCII for \r (carriage ret.)
                JSR             write_byte_sci  ; write it to SCI
                LDAB            #$0A            ; load B with ASCII for \n (new line)
                JSR             write_byte_sci  ; write it to SCI
                PULB                            ; pull B back from stack
                RTS                             ; return

; ******************************************************************************** 
; SUBROUTINE: write_str_sci
; ARGS: X: the address of the start of the string to write
; writes a null-terminated (ending in #$00) string to the serial communications
; interface
; ********************************************************************************
write_str_sci:
                PSHB                            ; put B on the stack in case it's in use
                LDAB            X               ; load B with value at address in X
write_str_sci_L:
                JSR             write_byte_sci  ; write the character to the SCI
                INX                             ; increment X along the string
                LDAB            X               ; load B with the value at address in X
                CMPB            #$00            ; compare the current char with #$00
                BNE             write_str_sci_L ; if the char is the null char, exit the loop

                PULB                            ; pull B back from the stack
                RTS                             ; return

; ********************************************************************************
; SUBROUTINE: write_byte_sci
; ARGS: B: the ASCII character to write 
; writes one byte to the serial communications interface
; keeps polling until the TDRE byte is 1, then writes it
; ********************************************************************************
write_byte_sci:
                PSHA                            ; put A on the stack in case it's in use
write_byte_sci_L:
                LDAA            SCI1SR1         ; poll the SCI status register
                ANDA            #TDRE_bitmask   ; isolate the TDRE bit
                ; if TDRE is 0, keep polling:
                BEQ             write_byte_sci_L 
                STAB            SCI1DRL         ; TDRE is 1, so write the data
                
                PULA                            ; pull A back from the stack
                RTS                             ; return
                
; ******************************************************************************** 
; ISR: isr_sci_receive
; ********************************************************************************
isr_sci_receive:
                LDAA            SCI1SR1         ; poll the SCI status register
                LDAB            SCI1DRL         ; load in the 8 bits of data
                LDAA            ADJUST_STATE    ; load which parameter we should be adjusting

                ; if it's 0, we should be adjusting the period:
                CMPA            #$00
                BEQ             isr_sci_receive_period
                ; otherwise, we should be adjusting the duty cycle:
                BNE             isr_sci_receive_duty_cycle
                
isr_sci_receive_period:
                ; if the data is ASCII 'w', increase period by 1 ms
                CMPB            #ASCII_w
                BEQ             isr_sci_receive_period_inc
                ; if the data is ASCII 's', decrease period by 1 ms
                CMPB            #ASCII_s
                BEQ             isr_sci_receive_period_dec
                ; if the data is ASCII carriage return, switch to adjusting the
                ; duty cycle and then return
                CMPB            #ASCII_CR
                BEQ             isr_sci_receive_switch_adjust

isr_sci_receive_duty_cycle:
                ; if the data is ASCII 'w', increase the 8 bit DC by 1
                CMPB            #ASCII_w
                BEQ             isr_sci_receive_duty_cycle_inc
                ; if the data is ASCII 's', decrease the 8 bit DC by 1
                CMPB            #ASCII_s
                BEQ             isr_sci_receive_duty_cycle_dec
                ; if the data is ASCII carriage return, switch to adjusting the
                ; period and then return from interrupt
                CMPB            #ASCII_CR
                BEQ             isr_sci_receive_switch_adjust

; increment the period
isr_sci_receive_period_inc:
                LDD             PERIOD          ; add PERIOD_DEL to PERIOD
                ADDD            #PERIOD_DEL
                STD             PERIOD          ; and store it again
                LDAB            DUTY_CYCLE_8
                JSR             compute_duty_cycle  ; recompute the duty cycle
                BRA             isr_sci_receive_end

; decrement the period
isr_sci_receive_period_dec:
                LDD             PERIOD          ; sub PERIOD_DEL from PERIOD
                SUBD            #PERIOD_DEL
                STD             PERIOD          ; and store it again
                LDAB            DUTY_CYCLE_8
                JSR             compute_duty_cycle  ; recompute the duty cycle
                BRA             isr_sci_receive_end

; increment the duty cycle
isr_sci_receive_duty_cycle_inc:
                LDAB            DUTY_CYCLE_8
                ADDB            #DC_DEL         ; add DC_DEL to the duty cycle
                STAB            DUTY_CYCLE_8
                JSR             compute_duty_cycle  ; and recompute it
                BRA             isr_sci_receive_end

; decrement the duty cycle
isr_sci_receive_duty_cycle_dec:
                LDAB            DUTY_CYCLE_8
                SUBB            #DC_DEL         ; sub DC_DEL from the duty cycle
                STAB            DUTY_CYCLE_8
                JSR             compute_duty_cycle  ; and recompute it
                BRA             isr_sci_receive_end

; 'Enter' was pressed: invert ADJUST_STATE
isr_sci_receive_switch_adjust:
                LDAA            ADJUST_STATE
                EORA            #$01
                STAA            ADJUST_STATE
                CMPA            #$00
                BEQ             isr_sci_receive_message_period
                BNE             isr_sci_receive_message_duty_cycle

; print the message for adjusting the period
isr_sci_receive_message_period:
                LDX             #period_str
                BRA             isr_sci_receive_message_write

; print the message for adjusting the duty cycle
isr_sci_receive_message_duty_cycle:
                LDX             #dc_str

; write the message, then write the newline characters
isr_sci_receive_message_write:
                JSR             write_str_sci
                JSR             write_newline_sci
                BRA             isr_sci_receive_end

isr_sci_receive_end:
                RTI                             ; return

; ******************************************************************************** 
; ISR: isr_timer
; ********************************************************************************
isr_timer:
                LDAA            CYCLE_STATE     ; load the state of the cycle into A
                CMPA            #$00            ; compare it with zero
                MOVB            #$10,TFLG1      ; clear the channel 4 timer flag
                BEQ             isr_timer_high  ; if 0, write high

                ; if the CYCLES_LOW is 0, then just return
                LDD             CYCLES_LOW      ; load CYCLES_LOW into D, so we can compare it
                CPD             #$00            ; perform the comparison
                BEQ             isr_timer_end   ; branch if CYCLES_LOW does equal 0

                ADDD            TCNT            ; otherwise, add CYCLES_LOW to TCNT
                STD             TC4             ; and write the result to TC4
                MOVB            #$00,PTT        ; write LOW to PTT
                MOVB            #$00,CYCLE_STATE  ; switch CYCLE_STATE from 1 to 0
                BRA             isr_timer_end   ; return

isr_timer_high:
                ; if CYCLES_HIGH is 0, return
                LDD             CYCLES_HIGH     ; load CYCLES_HIGH into D, so we can compare it
                CPD             #$00            ; perform the comparison with 0
                BEQ             isr_timer_end   ; if CYCLES_HIGH = 0, just return

                ADDD            TCNT            ; otherwise, add CYCLES_HIGH to TCNT
                STD             TC4             ; and write the result to TC4
                MOVB            #$10,PTT        ; write HIGH to pin 4 of PTT
                MOVB            #$01,CYCLE_STATE  ; switch CYCLE_STATE from 0 to 1
                BRA             isr_timer_end   ; return
                
isr_timer_end:
                RTI                             ; return
