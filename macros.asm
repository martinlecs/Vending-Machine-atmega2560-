/*
 This file contains most of the macro definitions and register aliases, as well as .equ's
 */

.def temp = r16
.def data = r17
.def input = r18

; Registers needed for the keypad
.def row = r19
.def col = r20
.def rmask = r21
.def cmask = r22
.def temp2 = r23


.def current_selection = r14
.def current_price = r15
.def EXT_INT_FLAG = r13
.def DEBOUNCE_FLAG = r12
.def DEBOUNCE_COUNTER = r11
.def NEXT_SELECT = r10

; These symbols are used to change the LCD Address counter, allowing us to print wherever we want of the 2*16 panel
.equ LCD_ADDR_SET = 0b10000000
.equ LCD_LINE1 = 0
.equ LCD_LINE2 = 0x40

; VREG definitions
.equ START_FLAG = 0b00000001
.equ SELECT_FLAG = 0b00000010
.equ COIN_FLAG = 0b00000100
.equ DELIVER_FLAG = 0b00001000
.equ ABORT_FLAG = 0b00010000
.equ EMPTY_FLAG = 0b00100000
.equ ADMIN_FLAG = 0b01000000
.equ WAIT_FLAG = 0b10000000
.equ NEW_SELECTION = 0b01000010
.equ HASH_ADMIN = 0b01000011

; ACCFLAG definitions
.equ HASH_INT = 0b00000001
.equ NO_BUTTON = 0b00000010

; POTREG definitions
.equ START = 0b00000001
.equ END = 0b00000011
.equ RESTART = 0b00000000
.equ ENABLE = 0b10000000

; Matrix Keypad definitions
.equ PORTLDIR = 0xF0
.equ INITCOLMASK = 0xEF
.equ INITROWMASK = 0x01
.equ ROWMASK = 0x0F

; This macro reads an index in the INVENTORY array and makes a decision to branch based on the value inside the array
; If the item number == 0, we branch to SET_EMPTY which sets the EMPTY_FLAG, signalling to the program that we have run out of stock for the specified item
; If the item number > 0, we branch to SET_COIN which sets the COIN_FLAG, signalling to the program that we are able to purchase the item
; @0 represents an item from 1-9
.macro ReadArrayIndex
	mov input, @0							
	ldi ZL, low(INVENTORY)
	ldi ZH, high(INVENTORY)
	clr temp
loop:
	ld data, Z+
	inc temp
	cp temp, input
	brne loop
	cpi data, 0	
	breq SET_EMPTY
	rjmp SET_COIN
.endmacro

; This macro is the same algorithm as above but does not have any branches
; @0 represents an item from 1-9
; The value that is read from the array is stored in 'data' (r17)
 .macro GetInventory
	mov input, @0
	ldi ZL, low(INVENTORY)
	ldi ZH, high(INVENTORY)
	clr temp
loop:
	ld data, Z+
	inc temp
	cp temp, input
	brne loop
.endmacro


; This macro changes the quantity of on item by modifying the INVENTORY array
; @0 represents an item from 1-9. This number must be stored in a register
; @1 This register holds the new value that we want to change the inventory number to
.macro ChangeInventory
	mov input, @0	
	mov temp, input
	ldi ZL, low(INVENTORY)
	ldi ZH, high(INVENTORY)
	subi temp, 1
	add ZL, temp		; We only need to add the lower address, this to get the right displacement from the starting address
	st Z, @1
.endmacro

; This macro changes the quantity of on item by modifying the IPRICE array
; @0 represents an item from 1-9. This number must be stored in a register
; @1 This register holds the new value that we want to change the inventory number to
.macro ChangePriceIndex
	mov input, @0	
	mov temp, input
	ldi ZL, low(PRICES)
	ldi ZH, high(PRICES)
	/*
	clr temp
loop:
	inc temp
	cp temp, input
	brne loop
	*/
	; once equal
	subi temp, 1
	add ZL, temp
	//adc ZH, temp
	st Z, @1
.endmacro

; This macro reads the price of on item and stores it into data (r17)
; @0 represents an item from 1-9. This number must be stored in a register
.macro ReadPriceIndex
	mov input, @0		
	ldi ZL, low(PRICES)
	ldi ZH, high(PRICES)
	clr temp
loop:
	ld data, Z+
	inc temp
	cp temp, input
	brne loop
.endmacro

.macro ShowCoins
	cpi temp, @0
	brne @1
	ldi temp, @2
	out PORTC, temp
.endmacro

; This Macro is used when we need to wait for user input to do something, as well as manage other tasks (such as printing to the screen or showing LEDS)
; @0 represents the Label that we want to jump to whenever the we complete the read cycle
; This provides extra flexbility in allowing us where to specify the output is used for
; The output is stored in a register defined as "input" (r18)
.macro keypadSKIP
HandleInput1:
	ldi cmask, INITCOLMASK
	clr col
colloop1:
	cpi col, 4	
	brne CONTINUE
	jmp @0
CONTINUE:		
	sts PORTL, cmask
	ldi temp, 0xFF
delay1: 
	dec temp
	brne delay1
	lds temp, PINL
	andi temp, ROWMASK
	cpi temp, 0x0F
	breq nextcol1
	ldi rmask, INITROWMASK
	clr row
rowloop1:
	cpi row, 4
	breq nextcol1
	mov temp2, temp
	and temp2, rmask
	breq convert1
	inc row
	lsl rmask
	jmp rowloop1
nextcol1:
	lsl cmask
	inc col
	jmp colloop1
convert1:
	cpi col, 3
	breq letters1
	cpi row, 3
	breq symbols1
	mov temp, row
	lsl temp
	add temp, row
	add temp, col
	inc temp
	jmp convert_end1
letters1:
	ldi temp, 'A'
	add temp, row
	jmp convert_end1
symbols1:
	cpi col, 0 ; check if we have a star
	breq star1
	cpi col, 1 ; or if we have zero
	breq zero1
	cpi col, 2
	breq hash1
	jmp @0
star1:
	ldi temp, '*'
	jmp convert_end1
zero1:
	ldi temp, 0x00
	jmp convert_end1
hash1:
	ldi temp, '#'
convert_end1:
	mov input, temp
.endmacro

; clears a 2 byte address in the dseg
.macro clear
    ldi YL, low(@0)
    ldi YH, high(@0)
    clr temp
    st Y+, temp
    st Y, temp
.endmacro

;
; LCD related macro
;

;Macro do_lcd_command: Write a command to the LCD. The data reg stores the value to be written.
.macro do_lcd_command
	ldi r16, @0
	rcall lcd_command
	rcall lcd_wait
.endmacro

;Macro do_lcd_data: Write a character to the LCD. The data reg stores the value to be written.
.macro do_lcd_data
	ldi r16, @0
	rcall lcd_data
	rcall lcd_wait
.endmacro

.macro do_lcd_data_register
	mov r16, @0
	rcall lcd_data
	rcall lcd_wait
.endmacro