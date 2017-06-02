/*
 * keypad.asm
 *
 *  Created: 2/06/2017 12:12:14 AM
 *   Author: Martin Le
 */ 

 ;
; Matrix Keypad Functions
;
HandleInput:
	ldi cmask, INITCOLMASK
	clr col
colloop:
	cpi col, 4		; There are four rows
	breq HandleInput
	sts PORTL, cmask
	ldi temp, 0xFF
delay: 
	dec temp
	brne delay
	lds temp, PINL
	andi temp, ROWMASK
	cpi temp, 0x0F
	breq nextcol
	ldi rmask, INITROWMASK
	clr row
rowloop:
	cpi row, 4
	breq nextcol
	mov temp2, temp
	and temp2, rmask
	breq convert
	inc row
	lsl rmask
	jmp rowloop
nextcol:
	lsl cmask
	inc col
	jmp colloop
convert:
	cpi col, 3
	breq letters
	cpi row, 3
	breq symbols
	mov temp, row
	lsl temp
	add temp, row
	add temp, col
	inc temp
	jmp convert_end
letters:
	ldi temp, 'A'
	add temp, row
	jmp convert_end

symbols:
	cpi col, 0 ; check if we have a star
	breq star
	cpi col, 1 ; or if we have zero
	breq zero
	cpi col, 2
	breq hash
	jmp HandleInput
star:
	ldi temp, '*'
	jmp convert_end
zero:
	ldi temp, 0x00
	jmp convert_end
hash:
	out PORTC, temp
	ldi temp, '#'
convert_end:
	mov input, temp
	ret
