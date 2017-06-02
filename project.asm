.include "m2560def.inc"

.include "macros.asm"

.dseg
TempCounter: .byte 2
QuarterCounter: .byte 2
ButtonCounter: .byte 2
VREG: .byte 1
INVENTORY: .byte 9
PRICES: .byte 9
POTREG: .byte 1
COINS_INPUTED: .byte 1
ACCFLAGS: .byte 1
HASH_COUNTER: .byte 1
CURRENT_ITEM: .byte 1

.cseg
.org 0x00    
	jmp RESET
.org INT0addr
	jmp EXT_INT0
.org INT1addr
	jmp EXT_INT1
.org OVF0addr
    jmp Timer0OVF
.org ADCCaddr
	jmp ADCC_INT

DEFAULT:    reti

RESET:
    ldi temp, high(RAMEND)
    out SPH, temp
    ldi temp, low(RAMEND)
    out SPL, temp

; Set up LEDS
    ser temp
    out DDRC, temp
	out DDRG, temp
	ldi temp, 1
	out PORTC, temp

; Set VREG
	lds temp, VREG
	ldi temp, START_FLAG
	sts VREG, temp

; Set up initial Inventory 1-9
	clr data
	ldi ZL, low(INVENTORY)
	ldi ZH, high(INVENTORY)
	cycle:
		inc data
		mov temp, data
		//ldi temp, 0		//replace array with zeros
		st Z+, temp
		cpi data, 9
		brne cycle

; Set up prices (hard-coded)
	clr data
	ldi ZL, low(PRICES)
	ldi ZH, high(PRICES)
	set_prices:
		inc data
		mov temp, data	
		lsr temp
		brcs ODD		; Tests Carry Flag
		ldi temp, 2
		st Z+, temp		; even numbers do not have a carry bit
		cpi data, 9		
		brne set_prices
		rjmp price_exit
	ODD:
		ldi temp, 1
		st Z+, temp
		cpi data, 9
		brne set_prices

price_exit:		//More cheating

; Clear counters, just in case
    clear TempCounter           ; Initialise temporary counter to 0
    clear QuarterCounter         ; Initialise second counter to 0
	clr temp
	sts COINS_INPUTED, temp
	ldi temp, 0
	mov current_selection, temp
	clr DEBOUNCE_COUNTER
	clr current_price
	clr temp
	sts HASH_COUNTER, temp

; Set up for Timer0
	clr temp
	ldi temp, 0b00000000
	out TCCR0A, temp
	ldi temp, 0b00000010
	out TCCR0B, temp
	ldi temp, 1<<TOIE0
	sts TIMSK0, temp

; configure timer 3
	ldi temp, (1 << CS30)
	sts TCCR3B, temp
	ldi temp, (1<<WGM30)|(1<<COM3B1)
	sts TCCR3A, temp
	ser temp
	out DDRE, temp

	clr temp
	sts OCR3BL, temp
	sts OCR3BH, temp
	

; Set up POT hardware
	ldi temp, (3<<REFS0 | 0<<ADLAR | 0<<MUX0)
	sts ADMUX, temp
	ldi temp, (1<<MUX5)
	sts ADCSRB, temp
	;ldi temp, (1<<ADEN | 1<<ADSC | 1<<ADIE | 5<<ADPS0)				; Ruins lcd somehow
	sts ADCSRA, temp


; Set up external interrupts
	ldi temp, (2<<ISC10 | 2<<ISC00)	; set INT0/1 as falling-edge triggered interrupt
	sts EICRA, temp
	in temp, EIMSK					; no real need to do this? Can just write directly to register def
	ori temp, (1<<INT1 | 1<<INT0)
	out EIMSK, temp

; Set up Keypad
	ldi temp, PORTLDIR
	sts DDRL, temp

; Set up LCD
    ser temp
    out DDRF, temp
    out DDRA, temp
    clr temp
    out PORTF, temp
    out PORTA, temp

    do_lcd_command 0b00111000 ; 2x5x7
    rcall sleep_5ms
    do_lcd_command 0b00111000 ; 2x5x7
    rcall sleep_1ms
    do_lcd_command 0b00111000 ; 2x5x7
    do_lcd_command 0b00111000 ; 2x5x7
    do_lcd_command 0b00001000 ; display off
    do_lcd_command 0b00000001 ; clear display
    do_lcd_command 0b00000110 ; increment, no display shift
    do_lcd_command 0b00001100 ; Cursor on, bar, no blink

	rcall sleep_1ms
	do_lcd_data '2'
	do_lcd_data '1'
	do_lcd_data '2'
	do_lcd_data '1'
	do_lcd_data ' '
	do_lcd_data '1'
	do_lcd_data '7'
	do_lcd_data 's'
	do_lcd_data '1'
	do_lcd_data ' '
	do_lcd_data ' '
	do_lcd_data ' '
	do_lcd_data ' '
	do_lcd_data ' '
	do_lcd_data 'L'
	do_lcd_data '7'

	do_lcd_command LCD_ADDR_SET | LCD_LINE2	; move cursor to second line
	rcall sleep_1ms
	do_lcd_data 'V'
	do_lcd_data 'e'
	do_lcd_data 'n'
	do_lcd_data 'd'
	do_lcd_data 'i'
	do_lcd_data 'n'
	do_lcd_data 'g'
	do_lcd_data ' '
	do_lcd_data 'M'
	do_lcd_data 'a'
	do_lcd_data 'c'
	do_lcd_data 'h'
	do_lcd_data 'i'
	do_lcd_data 'n'
	do_lcd_data 'e'

    sei

MAIN:
	lds temp, VREG
	cpi temp, SELECT_FLAG
	brne CheckForKey
	rjmp SEL_REACH

CheckForKey:
	keypadSKIP MAIN
	cpi input, '#'
	brne SET_SELECT

MAIN_LOOP:
	rjmp MAIN

SEL_REACH:
	rjmp SELECT

SET_SELECT:
	ldi temp, SELECT_FLAG
	sts VREG, temp
	rjmp MAIN


Timer0OVF:
    in temp, SREG
    push temp
	push r25
	push r24

    lds r24, TempCounter       ; count the number of interrupts
    lds r25, TempCounter+1
    adiw r25:r24,1

	; Check if a millisecond has passed
	cpi r24, low(20)			; 10 * 128us = 1280us = 1.28ms
	ldi temp, high(20)
	cpc r25, temp
	brne QuarterSecond
	rcall DEBOUNCER

	QuarterSecond:
    cpi r24, low(7812/4)          ; Check if quarter second has passed
    ldi temp, high(7812/4)
    cpc r25, temp
    brne NotQuarter

    clear TempCounter			; After quarter second, clear temp counter

    lds r24, QuarterCounter     ; If a quarter second has passed, increase the counter
    lds r25, QuarterCounter+1
    adiw r25:r24, 1

	CheckQuart:
	cpi r24, low(1)
	ldi temp, high(1)
	cpc r25, temp
	brne CheckHalfSec
	rcall QuartCheck

	CheckHalfSec:
	; Check if half a second has passed
	cpi r24, low(2)
	ldi temp, high(2)
	cpc r25, temp
	brne Check1HalfSec
	rcall HalfCheck

	Check1HalfSec:
	; Check if 1.5 seconds have passed - This function is for turning off leds for 1.5s during Empty Screen
	cpi r24, low(5)				//Normally is 6
	ldi temp, high(5)
	cpc r25, temp
	brne Check3Seconds
	rcall CheckEmptyFlag

	Check3Seconds:
	; Check if 3 seconds have passed
    cpi r24, low(10)			; normally should be 12 butneed to subtract half a second to account for setup time.
    ldi temp, high(10)
    cpc r25, temp
	brne EndEP
	rcall Wait3Sec
	
	EndEP:
	sts QuarterCounter, r24
    sts QuarterCounter+1, r25
	rjmp Epilogue

NotQuarter:
    sts TempCounter, r24
    sts TempCounter+1, r25

Epilogue:
    pop r24
    pop r25
	pop temp
    out SREG, temp
    reti

DEBOUNCER:
	lds temp, POTREG
	cpi temp, ENABLE
	breq POT_READ

	ser temp
	cp DEBOUNCE_FLAG, temp		; Checks to see if Debounce flag has been set
	brne EXIT_DEBOUNCE
	; If debounce flag has been set, increment counter
	inc DEBOUNCE_COUNTER
	clr DEBOUNCE_FLAG
EXIT_DEBOUNCE:	
	ret

QuartCheck:
	lds temp, ACCFLAGS
	cpi temp, HASH_INT
	breq HASH_INT_HANDLER
	ret

HASH_INT_HANDLER:
	lds temp, HASH_COUNTER
	sts HASH_COUNTER, temp
	clr temp
	sts ACCFLAGS, temp
	ret

HalfCheck:
	lds temp, ACCFLAGS
	cpi temp, HASH_INT
	breq HASH_INT_HANDLER
	ret

; This function doesn't work as intended
POT_READ:
	lds ZL, ADCL
	lds ZH, ADCH

	; If the value has reached some threshold, it will set flags accordingly

	cpi ZL, low(0x003)			; Current problem, we're not reading anything from 
	ldi temp, high(0x003)
	cpc XH, temp
	brlt AT_START

	cpi ZL, low(0x3FB)
	ldi temp, high(0x3FB)
	cpc XH, temp
	brge AT_END

	ret

AT_START:
	ldi temp, START
	sts POTREG, temp
	ret

AT_END:
	ldi temp, END
	sts POTREG, temp
	ret

Wait3Sec:
	lds temp, VREG

	; Check for start flag
	cpi temp, START_FLAG
	breq START_UP

	; Check for Empty flag
	cpi temp, EMPTY_FLAG
	breq SELECT_CONFIG

	; Check for deliver flag
	cpi temp, DELIVER_FLAG
	breq SELECT_CONFIG

	ret

CheckEmptyFlag:
	; If the VREG flag is set to EMPTY_FLAG, turn off leds
	lds temp, VREG
	cpi temp, EMPTY_FLAG
	breq TURN_OFF_LEDS

	cpi temp, DELIVER_FLAG
	breq TURN_OFF_LEDS

	ret

; Turns off leds for Deliver mode
TURN_OFF_LEDS:
	clr temp
	out PORTC, temp
	out PORTG, temp
	ret
	
SELECT_CONFIG:
	clr temp
	sts OCR3BL, temp		  ; Will turn off the motor when you return to the select screen after 3 seconds
	ldi temp, SELECT_FLAG	  ; Sets the "Select" flag
	sts VREG, temp
	ret

; Start up screen
START_UP:
	ldi temp, SELECT_FLAG	  ; Sets the "Select" flag
	sts VREG, temp
	ret

EMPTY:
	clear TempCounter			; Reset counters to 0
	clear QuarterCounter

	ldi temp, EMPTY_FLAG		; Will jump back to select in 3 seconds
	sts VREG, temp
	ser temp
	out PORTC, temp	
	ldi temp, 0b00000011
	out PORTG, temp

	do_LCD_command 0x00000001
	rcall sleep_1ms
	do_lcd_data 'O'
	do_lcd_data 'u'
	do_lcd_data 't'
	do_lcd_data ' '
	do_lcd_data 'o'
	do_lcd_data 'f'
	do_lcd_data ' '
	do_lcd_data 's'
	do_lcd_data 't'
	do_lcd_data 'o'
	do_lcd_data 'c'
	do_lcd_data 'k'

	do_lcd_command LCD_ADDR_SET | LCD_LINE2	; move cursor to second line
	rcall sleep_1ms

	lds temp, CURRENT_ITEM			; gets the item that was selected on the Select Screen										
	subi temp, -'0'
	do_lcd_data_register temp			; prints that item number out on line 2

WAIT_FOR_SKIP:	
	ldi input, 0xFF
	
	keypadSkip WAIT_FOR_SKIP
	
	cpi input, 0xFF
	brne SELECT

	lds temp, VREG
	cpi temp, SELECT_FLAG
	breq SELECT

	rjmp WAIT_FOR_SKIP

SELECT:

	ldi temp, WAIT_FLAG
	sts VREG, temp
	out PORTC, temp
	
	RESET_COINS:
	; Reset number of coins inputed
	clr temp
	sts COINS_INPUTED, temp
	out PORTG, temp
	sts HASH_COUNTER, temp

	do_LCD_command 0x00000001
	rcall sleep_1ms
	do_lcd_data 'S'
	do_lcd_data 'e'
	do_lcd_data 'l'
	do_lcd_data 'e'
	do_lcd_data 'c'
	do_lcd_data 't'
	do_lcd_data ' '
	do_lcd_data 'i'
	do_lcd_data 't'
	do_lcd_data 'e'
	do_lcd_data 'm'
	rjmp KEYPAD_SELECT

HASH_INTERRUPT:
	
	cpi input, 'A'
	breq JUMP_ADMIN
	rjmp KEYPAD_SELECT

JUMP_ADMIN:
	jmp ADMIN_MODE

	/* The following code doesn't work
	cpi input, '#'
	brne KEYPAD_SELECT		; Go back and wait for more input
	; Set flag
	ldi temp, HASH_INT
	sts ACCFLAGS, temp
	clear TempCounter
	clear QuarterCounter
	*/
KEYPAD_SELECT:
	
	lds temp, HASH_COUNTER
	cpi temp, 20			; have to keep pressing the button until we hit 20
	brne Keypad_CONT
	jmp ADMIN_MODE

Keypad_CONT:
	keypadSKIP KEYPAD_SELECT

	cpi input, 1
	brge NEXT
	rjmp HASH_INTERRUPT
NEXT:
	cpi input, 10
	brlo NEXT2
	rjmp HASH_INTERRUPT 

NEXT2:
	sts CURRENT_ITEM, input
	ReadArrayIndex input

NextScreen:
	cpi temp, COIN_FLAG
	breq COIN
	rjmp EMPTY

SET_COIN:
	ldi temp, COIN_FLAG		; There is inventory to sell
	sts VREG, temp
	rjmp NextScreen

SET_EMPTY:
	ldi temp, EMPTY_FLAG		; There is inventory to sell
	sts VREG, temp
	rjmp NextScreen

COIN:

	ldi temp, COIN_FLAG
	sts VREG, temp

	do_LCD_command 0x00000001
	rcall sleep_1ms
	do_lcd_data 'I'
	do_lcd_data 'n'
	do_lcd_data 's'
	do_lcd_data 'e'
	do_lcd_data 'r'
	do_lcd_data 't'
	do_lcd_data ' '
	do_lcd_data 'C'
	do_lcd_data 'o'
	do_lcd_data 'i'
	do_lcd_data 'n'
	do_lcd_data 's'

	do_lcd_command LCD_ADDR_SET | LCD_LINE2	; move cursor to second line
	rcall sleep_1ms

	; Display number of coins to input
	ReadPriceIndex input		; Input hasn't been changed
	subi data, -'0'
	do_lcd_data_register data

	; Enable Potentiometer readings
	ldi temp, ENABLE
	sts POTREG, temp

	clear TempCounter
	clear QuarterCounter
	clr temp
	sts COINS_INPUTED, temp


WAIT_FOR_COINS:

	keypadSkip POT_CHECKER		; Will loop through keypad skip until a button is pressed.
	cpi input, '#'
	breq SELECT_REACH

	cpi input, 'D'
	breq INSERT_COIN
	rjmp WAIT_FOR_COINS


POT_CHECKER:

; process some other stuff
	
	lds temp, COINS_INPUTED
	
	Coin0:
		ShowCoins 0, Coin1, 0
	Coin1:
		ShowCoins 1, Coin2, 0b00000001
	Coin2:
		ShowCoins 2, Coin3, 0b00000011
	Coin3:
		ShowCoins 3, COIN_END, 0b00000111

/*
	lds temp, CURRENT_ITEM
	ReadPriceIndex temp
	lds temp, COINS_INPUTED
	sub data, temp		

	do_lcd_command LCD_ADDR_SET | LCD_LINE2	; move cursor to second line
	rcall sleep_1ms
	subi data, -'0'
	do_lcd_data_register data
	*/

	; Get all items to go to deliver screen, might just have to hard code this
	; Make sure you can reach every screen 
	; Increase max capacity to 255
	; Document everything

	lds row, COINS_INPUTED
	lds temp2, CURRENT_ITEM
	ReadPriceIndex temp

	cp row, temp2
	breq DELIVER_ITEM

COIN_END:
	rjmp WAIT_FOR_COINS

SELECT_REACH:
	rjmp SELECT

INSERT_COIN:
	lds temp, CURRENT_ITEM
	ReadPriceIndex temp

	lds temp, COINS_INPUTED
	cp temp, data
	breq COIN_END
	inc temp
	sts COINS_INPUTED, temp
	rjmp POT_CHECKER

DELIVER_ITEM:
	jmp DELIVER

DELIVER:

	clear TempCounter
	clear QuarterCounter

	ldi temp, DELIVER_FLAG
	sts VREG, temp
	
	; flash leds
	ser temp
	out PORTC, temp
	ldi temp, 0b00000011
	out PORTG, temp

	; spin Motor at full speed
	ser temp
	sts OCR3BL, temp

	; reset the POTREG
	ldi temp, RESTART
	sts POTREG, temp

	do_LCD_command 0x00000001
	rcall sleep_5ms
	do_lcd_data 'D'
	do_lcd_data 'e'
	do_lcd_data 'l'
	do_lcd_data 'i'
	do_lcd_data 'v'
	do_lcd_data 'e'
	do_lcd_data 'r'
	do_lcd_data 'i'
	do_lcd_data 'n'
	do_lcd_data 'g'
	do_lcd_data ' '
	do_lcd_data 'i'
	do_lcd_data 't'
	do_lcd_data 'e'
	do_lcd_data 'm'

	;do some calculations
	lds temp2, CURRENT_ITEM
	GetInventory temp2			; this is doing the right thing

	dec data

	lds temp2, CURRENT_ITEM
	ChangeInventory temp2, data

	; Clear timer counters
	clear QuarterCounter
	clear TempCounter

DELIVER_LOOP:
	lds temp, VREG
	cpi temp, SELECT_FLAG
	brne DELIVER_LOOP2
	jmp SELECT

DELIVER_LOOP2:
	rjmp DELIVER_LOOP



COIN_RETURN:
	rjmp COIN_RETURN


ADMIN_MODE:

	//Set admin mode flag
	ldi temp, ADMIN_FLAG
	sts VREG, temp

	//Reset Hash_counter
	clr temp
	sts HASH_COUNTER, temp
	
	//Clear PORTG lights
	out PORTG, temp

	do_LCD_command 0x00000001
	rcall sleep_1ms
	do_lcd_data 'A'
	do_lcd_data 'd'
	do_lcd_data 'm'
	do_lcd_data 'i'
	do_lcd_data 'n'
	do_lcd_data ' '
	do_lcd_data 'm'
	do_lcd_data 'o'
	do_lcd_data 'd'
	do_lcd_data 'e'
	do_lcd_data ' '

	//Check for some other flag
	ldi temp, NEW_SELECTION
	cp NEXT_SELECT, temp
	breq NEW_SELECT_ITEM

	ldi temp, 1	; Starting value is always 1
	mov current_selection, temp
	mov input, current_selection
	rjmp INITIAL_SELECTION

NEW_SELECT_ITEM:	
	mov input, current_selection

INITIAL_SELECTION:
	subi input, -'0'
	do_lcd_data_register input

	do_lcd_command LCD_ADDR_SET | LCD_LINE2

	GetInventory current_selection ; Stores the value into 'data'

	; This section is for setting the leds to show inventory number
	cpi data, 0		
	brne MoreThanZero		; If there are more than 0 items
	clr temp
	out PORTC, temp			; If there are no items, clear LEDS
	rjmp CARRY_ON

	MoreThanZero:				; Loop to correctly display the right number of leds
	clr temp					; Set temp = 0
	ldi input, 0b00000000		; load the binary number 0 into input
		LED_LOOP:
			lsl input				; left shift input
			ori input, 0b00000001	; or the bits
			inc temp				; increment temp counter
			cp data, temp			; compare temp counter to data value
			brne LED_LOOP			; repeat the loop until the counters are equal
	
	out PORTC, input			; Write input to the leds
	cpi data, 9					; if data value > 9, increment extra leds
	brlo CARRY_ON				; if not continue
	rjmp SET_PORTG

; This section is for printing the inventory number onto the lcd screen
CARRY_ON:
	cpi data, 10			; Check if the amount of inventory is greater or equal to 10
	brge GreaterThanNine
	rjmp LessThanTen

GreaterThanNine:
//BUG: Doesn't increment 10s or 1s??
	mov temp, data
	clr temp2

	hundreds:
			cpi temp, 100
			brlo printHundreds
			inc temp2
			subi temp, 100
			rjmp hundreds
		printHundreds:
			subi temp2, -'0'
			do_lcd_data_register temp2
			clr temp2
		tens:
			cpi temp, 10
			brlo ones
			inc temp2

			do_LCD_command 0x00000001
			subi temp, -'0'
			do_lcd_data_register temp

			subi temp, 10
			rjmp tens
		ones:
			subi temp2, -'0'
			do_lcd_data_register temp2
			subi temp, -'0'
			do_lcd_data_register temp

	rjmp WritePrice

LessThanTen:				; If number is less than 10, it is an easy conversion
	subi data, -'0'
	do_lcd_data_register data // This is correct
	rcall sleep_5ms

WritePrice:
	//Set cursor on right hand side of screen
	do_lcd_command LCD_ADDR_SET | LCD_LINE2+14 // rather than doing this, might be better to set to end and left shift it each time you write something, then write capacity afterwards
	do_lcd_data '$'

	ReadPriceIndex current_selection

	mov current_price, data		// This is acccurate
	subi data, -'0'
	do_lcd_data_register data 

Observer:
	ser temp
	cp EXT_INT_FLAG, temp
	brne KEYPAD_CHECKER
	clr temp
	mov EXT_INT_FLAG, temp
	rjmp ADMIN_MODE

KEYPAD_CHECKER:
	keypadSKIP Observer

	cpi input, 1
	brge NUM1
	rjmp OTHER
	NUM1:
		cpi input, 10
		brlo NUM2
		rjmp OTHER 
	NUM2:
		mov current_selection, input	; Stores what number was selected into current_selection
		
		; Signal that a new selection has been made on the menu
		ldi temp, NEW_SELECTION
		mov NEXT_SELECT, temp			; This is probably a flag
		
		rjmp ADMIN_MODE

	OTHER:
		cpi input, 'A'
		breq COST_UP

		cpi input, 'B'
		breq COST_DOWN

		cpi input, 'C'
		breq FREE

		cpi input, '#'
		brne ADMIN_END
		rjmp SELECT

	ADMIN_END:
		rcall sleep_5ms
		rjmp ADMIN_MODE

; Only affecting the first index?? I dunno why
COST_UP:
	
	ReadPriceIndex current_selection	; gets correct price. Yep it does no need to check here
	cpi data, 3
	breq ADMIN_END			; If already at max value then jump to end of epilogue
	inc data
	ChangePriceIndex  current_selection, data ; <- problem is in here again
	rjmp ADMIN_END


COST_DOWN:
	ReadPriceIndex current_selection	; gets correct price. Yep it does no need to check here
	cpi data, 0
	breq ADMIN_END			; If already at max value then jump to end of epilogue
	dec data
	ChangePriceIndex  current_selection, data ; <- problem is in here again
	rjmp ADMIN_END

FREE:
	ldi data, 0
	ChangePriceIndex  current_selection, data
	rjmp ADMIN_END


SET_PORTG:
	cpi data, 9
	breq SET_9

	cpi data, 10
	breq SET_10

SET_9:
	ldi temp, 0b00000001
	out PORTG, temp
	rjmp CARRY_ON

SET_10:
	ldi temp, 0b00000011
	out PORTG, temp
	rjmp CARRY_ON


EXT_INT0:
	in temp, SREG
    push temp

	ser temp
	mov DEBOUNCE_FLAG, temp		; Set debounce flag to 0xFF

	ldi temp, 1
	cp DEBOUNCE_COUNTER, temp
	breq CONT_INT0
	rjmp EXT_INT0_EPILOGUE

CONT_INT0:
	clr DEBOUNCE_COUNTER
	clr DEBOUNCE_FLAG
	out PORTC, current_selection
	ser temp
	mov EXT_INT_FLAG, temp
	GetInventory current_selection ; value stored in 'data'
	cpi data, 255
	breq EXT_INT0_EPILOGUE
	inc data						; for every interrupt, increment data
	ChangeInventory current_selection, data

EXT_INT0_EPILOGUE:
	pop temp
	out SREG, temp
	reti


EXT_INT1:
	in temp, SREG
	push temp

	; Counter-based approach
	; Must reset counter back to 10 after interrupt is complete

	; Every time EXT_INT1 occurs, we set a flag
	; Timer0 checks every 250ms to see if this flag is still up, if it is, increment the counter 
	; if the flag is not up, decrement the counter
	; Timer0 only starts this inc/dec process once the flag is set

	; Set the debounce flag
	ser temp
	mov DEBOUNCE_FLAG, temp		; Set debounce flag to 0xFF

	//out PORTC, DEBOUNCE_COUNTER

	ldi temp, 1				
	cp DEBOUNCE_COUNTER, temp
	breq CONT_INT1
	rjmp EXT_INT1_EPILOGUE

CONT_INT1:

	; Reset the debounce counter for next time
	clr DEBOUNCE_COUNTER
	clr DEBOUNCE_FLAG
	ser temp
	mov EXT_INT_FLAG, temp
	GetInventory current_selection ; value stored in 'data'
	cpi data, 0
	breq EXT_INT1_EPILOGUE
	dec data						; for every interrupt, increment data
	ChangeInventory current_selection, data

EXT_INT1_EPILOGUE:
	pop temp
	out SREG, temp
	reti

ADCC_INT:
	in temp, SREG
	push temp

	lds temp, ADCSRA
	ori temp, (1<<ADSC)
	sts ADCSRA, temp

	pop temp
	out SREG, temp
	reti

.include "keypad.asm"

; LCD protocol control bits
.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4

.macro lcd_set
	sbi PORTA, @0
.endmacro

.macro lcd_clr
	cbi PORTA, @0
.endmacro


;
; LCD related functions
;

lcd_command:
	out PORTF, r16
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	lcd_clr LCD_E
	rcall sleep_1ms
	ret

lcd_data:
	out PORTF, r16
	lcd_set LCD_RS
	rcall sleep_1ms
	nop
	nop
	lcd_set LCD_E
	rcall sleep_1ms
	nop
	nop
	lcd_clr LCD_E
	rcall sleep_1ms
	nop
	nop
	lcd_clr LCD_RS
	ret

lcd_wait:
	push r16
	clr r16
	out DDRF, r16
	out PORTF, r16
	lcd_set LCD_RW
lcd_wait_loop:
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	in r16, PINF
	lcd_clr LCD_E
	sbrc r16, 7
	rjmp lcd_wait_loop
	lcd_clr LCD_RW
	ser r16
	out DDRF, r16
	pop r16
	ret

.equ F_CPU = 16000000
.equ DELAY_1MS = F_CPU / 4 / 1000 - 4
; 4 cycles per iteration - setup/call-return overhead

sleep_1ms:
	push r24
	push r25
	ldi r25, high(DELAY_1MS)
	ldi r24, low(DELAY_1MS)
delayloop_1ms:
	sbiw r25:r24, 1
	brne delayloop_1ms
	pop r25
	pop r24
	ret

sleep_5ms:
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	ret