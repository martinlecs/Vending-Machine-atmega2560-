.include "m2560def.inc"
 
.def leds = r16
.def temp = r17

; POTREG definitions
.equ START = 0b00000001
.equ END = 0b00000011
.equ RESTART = 0b00000000
 
; This macro clears a word (2 bytes) in memory.
; The parameter @0 is the memory address for that word
.macro clear
	ldi YL, low(@0)				; load memory address into Y
	ldi YH, high(@0)
	clr temp
	st Y+, temp					; clear two bytes at @0 in SRAM
	st Y, temp
.endmacro
 
.dseg
SecondCounter:					; 2-byte counter used for counting seconds
	.byte 2
TempCounter:					; 2-byte temporary counter used to determine if 1 second has passed
	.byte 2
POTREG: .byte 1
 
.cseg
.org 0x0000
	jmp RESET
	jmp DEFAULT					; No handling for IRQ0
	jmp DEFAULT					; No handling for IRQ1
.org OVF0addr
	jmp Timer0OVF				; jump to interrupt handler for Timer0 overflow
 
DEFAULT:
	reti						; used for interrupts that are not handled
 
RESET:
	ldi temp, high(RAMEND)		; initialise stack pointer
	out SPH, temp
	ldi temp, low(RAMEND)
	out SPL, temp
 
	ser temp 					; set temp to 0xFF
	out DDRC, temp				; set Port C as output

	clear TempCounter 			; clear temporary counter 
	clear SecondCounter 		; clear second counter
 
	ldi temp, 0b00000000 		; set all TCCR0A flags to 0
	out TCCR0A, temp
	ldi temp, 0b00000010		; set TCCR0A flags to select clock
	out TCCR0B, temp 			; 010 --- set prescaler to 8
	ldi temp, 1 << TOIE0 		; puts 1 in the TOIE0 flag 00000001
	sts TIMSK0, temp			; to enable timer
	sei 						; enable global interrupt

	rjmp main
 
Timer0OVF:						; interrupt subroutine to Timer0
	in temp, SREG
	push temp
	push YH						; in the prologue
	push YL
	push r25
	push r24
 
	lds r24, TempCounter 		; load value of temporary counter
	lds r25, TempCounter + 1
	adiw r25:r24, 1 			; increase temporary counter by 1
 
	cpi r24, low(7812/4)			; compare temporary counter with
	ldi temp, high(7812/4)		; 7812 = 10^6/128
	cpc r25, temp
	brne notSecond 				; a second hasnt passed
 
	clear TempCounter			; reset temporary counter
	lds r24, SecondCounter 		; load second counter and increase since 1 second has expired
	lds r25, SecondCounter + 1
	adiw r25:r24, 1 			; increase second counter by 1

	// Check if 1 second has passed
	cpi r24, low(1)				; 2 = half a second
	ldi temp, high(1)			; doesn't ever equal 0?
	cpc r25, temp
	breq POT_READ
 
	sts SecondCounter, r24
	sts SecondCounter + 1, r25
 
notSecond:
	sts TempCounter, r24		; store new value of temporary counter
	sts TempCounter + 1, r25
 
epilogue:
	pop r24
	pop r25
	pop YL
	pop YH
	pop temp
	out SREG, temp
	reti 	

POT_READ:

	; Set up POT hardware
	ldi temp, (3<<REFS0 | 0<<ADLAR | 0<<MUX0)
	sts ADMUX, temp
	ldi temp, (1<<MUX5)
	sts ADCSRB, temp
	ldi temp, (1<<ADEN | 1<<ADSC | 1<<ADIE | 5<<ADPS0)
	sts ADCSRA, temp

	lds ZL, ADCL
	lds ZH, ADCH

	clear SecondCounter
	rjmp epilogue
 
main:
	cpi ZL, low(0x000)
	ldi temp, high(0x000) ;0x004
	cpc ZH, temp
	brlt AT_START
	
	cpi ZL, low(0x3FF) ; 0x3FB
	ldi temp, high(0x3FF)
	cpc ZH, temp
	brge COIN_INSERTED

	rjmp main

AT_START:
	ldi temp, 0b00000011
	out PORTC, temp	
	rjmp main

COIN_INSERTED:
	ldi temp, 0b11000000
	out PORTC, temp
	rjmp main