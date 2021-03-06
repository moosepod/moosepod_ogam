        processor 6502
        include "vcs.h"
        include "macro.h"
        include "xmacro.h"

;;;;; All of the following were helpful in building this game:
;;;;; An Atari 2600 game! See http://8bitworkshop.com/
;;;;; Making Games for the Atari 2600 by Steven Hugg
;;;;;
;;;;; Scoreboard code and xmacro.h from there

;;;;; This is a 2600 template file. It draws a background color and
;;;;; that is it. Note that there are black areas in the overscan/underscan if
;;;;; run on stella. this is normal.


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables segment

        seg.u Variables
        org $80

GameState	byte ; Contains the main state of the game
STATE_START   equ 0
STATE_PLAYING equ 1
STATE_P1_WIN  equ 2
STATE_P2_WIN  equ 3

Score0	byte	; BCD score of player 0
Score1	byte	; BCD score of player 1

FontBuf	ds 10	; 2x5 array of playfield bytes

; high nibble is suit (0 diamond 1 spade 2 clubs 3 hearts)
; low nibble is card number 
Card0   byte    ; face-up card of player 0
Card1   byte    ; face-up card of player 1

SuitSpritePtr .word   ; Will store pointer to card suit sprite
CardSpritePtr .word

ButtonPressed byte ; used for debouncing

Temp	byte

CardSpriteH equ 7 ; horizontal position of card sprite
SuitSpriteH equ 8 ; horizontal position of suit sprite

Player0CardIndex byte ; index into deck below of P0 card
Player1CardIndex byte ; index into deck below of P1 card

DeckStart byte ; first byte of decks. 104 (52 * 2) bytes will be used for deck

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Code segment

        seg Code
        org $f000
		
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Setup
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Start
    CLEAN_START

	lda #STATE_START
	sta GameState

	jsr StartGame ; FOR TESTINGS

	lda #$00
	sta Score0
	lda #$00
	sta Score1
	lda #$00
	sta ButtonPressed

NextFrame
	VERTICAL_SYNC

; 37 lines BLANK
	TIMER_SETUP 37

	; Check reset switch. Start game if triggered
	lsr SWCHB ; This will shift bit 0 into Carry, which we can then test
	bcs NoReset
	jsr StartGame

NoReset	
	lda Score0
    ldx #0
	jsr GetBCDBitmap
	lda Score1
    ldx #5
	jsr GetBCDBitmap

	; Move player1 sprite to correct location to draw suit
	ldx #SuitSpriteH
	sta WSYNC
Sprite1Loop
	dex
	bne Sprite1Loop
	sta RESP0

	; Move player2 sprite to correct location to draw card
	ldx #CardSpriteH
	sta WSYNC
Sprite2Loop
	dex
	bne Sprite2Loop
	sta RESP1

;;; 192 lines total. First 40 are scoreboard
    TIMER_WAIT	
	TIMER_SETUP 50

	; Draw the score no matter what the state
	jsr DrawScoreboard

    TIMER_WAIT	

	; Jump to logic for each game state. We have 122 lines left at this point. Each
	; subroutine must handle its own lines. Logic is to keep subtracting, and when x goes 
	; below zero, jump to the appropriate subroutine
	ldx GameState
	dex 
	bpl GameStateNext1
	jmp StartStateKernel
GameStateNext1 
	dex
	bpl GameStateLoopReturn
	jmp PlayingStateKernel
GameStateLoopReturn

; 30 lines overscan
	TIMER_SETUP 30
    TIMER_WAIT	

    jmp NextFrame

;;;
;;; Change the game state to started after initializing variables
;;;
StartGame subroutine
	lda #STATE_PLAYING
	sta GameState

	; Initialize scores
	lda #$00
	sta Score0
	lda #$00
	sta Score1

	; Initialize cards
	lda #$11
	sta Card0
	lda #$21
	sta Card1
	
	; Clear button debounce
	lda #$00
	sta ButtonPressed

	;; Initialize deck.
	lda #0
	sta Player0CardIndex

	; Setup the 4 suits of cards
	lda #0
	jsr SetupCardSuit
	lda #$10
	jsr SetupCardSuit
	lda #$20
	jsr SetupCardSuit
	lda #$30
		jsr SetupCardSuit

	; Reset counter and setup initial deck
	lda #0
	sta Player0CardIndex
	lda DeckStart
	sta Card0

	rts

SetupCardSuit subroutine
	; Setup next suit of cards. Expects suit to be put on accumulator
	sta Temp
	ldy #13
.CardSetupLoop
	ldx Player0CardIndex
	tya
	adc Temp ; this will add the suit (stored in high nibble) onto the base card
	sta DeckStart,x
	inc Player0CardIndex
	dey
	bpl .CardSetupLoop
	rts

;;;
;;; Kernel for game in initial starting state (no game started)
;;;

StartStateKernel
	;;;;; Draw the card decks. 

	lda #%00000011	; score mode + reflect playfield
	sta CTRLPF

	; top of cards
	TIMER_SETUP 100
	lda #$41
	sta COLUPF

	lda PFData0
	sta PF0

	lda PFData1
	sta PF1

	lda PFData2
	sta PF2

    TIMER_WAIT

; Remaining lines -- 192-50-100. Draw no playfield
	TIMER_SETUP 32
	lda #%00
	sta PF0
	sta PF1
	sta PF2
	TIMER_WAIT
	
	jmp GameStateLoopReturn

;;;
;;; Kernel for the game in playing state
;;;
PlayingStateKernel
	;;;;; Draw the card decks. 
	lda #%00000011	; score mode + reflect playfield
	sta CTRLPF

	; Check button press with debounce
	bit INPT4
	bmi .SkipP0Button
	bit ButtonPressed
	bmi .ButtonStillPressed

	; button is pressed, so pick next card
	inc Player0CardIndex
	ldx Player0CardIndex
	lda DeckStart,x
	sta Card0
	lda #$FF
	sta ButtonPressed
	jmp .ButtonStillPressed

.SkipP0Button
	lda #0
	sta ButtonPressed
.ButtonStillPressed

	; top of cards
	TIMER_SETUP 10
	lda #$41
	sta COLUPF

	lda PFData0
	sta PF0

	lda PFDataFlipped1
	sta PF1

	lda PFDataFlippedEnd2
	sta PF2

    TIMER_WAIT

	; middle of cards
	TIMER_SETUP 5

	lda PFDataFlippedMiddle2
	sta PF2

    TIMER_WAIT

	TIMER_SETUP 35

	; Pull suit number (0-3) from high nibble and convert to offset into sprite
	; table using a lookup table
	lda Card0
	and #$F0 ; take high nibble
	lsr ; move to low nibble
	lsr ; move to low nibble
	lsr ; move to low nibble
	lsr ; move to low nibble
	tay
	lda SuitSpritesIndex,y

	; Calculate sprite address for suit for P1, with offset from calcuation above. 
	; Offset in A
	; remember low byte of address is in left hand side of item, not right

	clc
	adc #<SuitSprites
	sta SuitSpritePtr

	lda #>SuitSprites
	adc #0 ; high byte will be 0 but we still need the carry
	sta SuitSpritePtr+1

	; Repeat process for card sprite
	lda Card0
	and #$0F
	tay
	lda CardSpritesIndex,y
	clc
	adc #<CardSprites
	sta CardSpritePtr
	lda #>CardSprites
	adc #0 ; high byte will be 0 but we still need the carry
	sta CardSpritePtr+1

	; Draw the sprite for the card suit and card number for P1
	ldy #7
SpriteLoopP1 
	sta WSYNC
	lda (SuitSpritePtr),y
	sta GRP0
	lda (CardSpritePtr),y
	sta GRP1
	dey
	bpl SpriteLoopP1

	sta WSYNC
	lda #0
	sta GRP0
	sta GRP1
    TIMER_WAIT

	TIMER_SETUP 40

	; Draw the sprite for the card suit and card number for P2. First we need to shift
	; the sprite positions over to the right

	; Move player1 sprite to correct location to draw suit
	ldx #SuitSpriteH
	inx
	inx
	inx
	sta WSYNC
Sprite1Loop2
	dex
	bne Sprite1Loop2
	sta RESP0

	; Move player2 sprite to correct location to draw card
	ldx #CardSpriteH
	inx
	inx
	inx
	sta WSYNC
Sprite2Loop2
	dex
	bne Sprite2Loop2
	sta RESP1

	; Assign fine adjustment (arrived at by trial and error)
	lda #$50
	sta HMP0
	sta HMP1
	sta HMOVE

	; space P2 sprites farther down
	ldx 24
SpaceLoop
	dex
	sta WSYNC
	bne SpaceLoop

	; now draw the sprites
	ldy #8	
SpriteLoopP2
	sta WSYNC
	lda SuitSprites,y
	sta GRP0
	lda CardSprites,y
	sta GRP1
	dey
	bpl SpriteLoopP2
	sta WSYNC
	lda #0
	sta GRP0
	sta GRP1
	TIMER_WAIT

	; bottom of cards
	TIMER_SETUP 10

	lda PFDataFlippedEnd2
	sta PF2

    TIMER_WAIT

; Remaining lines -- 192-50-100
	TIMER_SETUP 32
	lda #%00
	sta PF0
	sta PF1
	sta PF2
	TIMER_WAIT
	
	jmp GameStateLoopReturn

;;;
;;; Draw the scoreboard
;;;
DrawScoreboard subroutine
	; Put the playfield into score mode (bit 2) which gives
	; two different colors for the left/right side of
	; the playfield (given by COLUP0 and COLUP1).
	lda #%00010010	; score mode + 2 pixel ball
	sta CTRLPF
	lda #$48
	sta COLUP0	; set color for left
	lda #$a8
	sta COLUP1	; set color for right

	; Now we draw all four digits.
	ldy #0		; Y will contain the frame Y coordinate
ScanLoop1a
	sta WSYNC
	tya
	lsr		; divide Y by two for double-height lines
	tax		; -> X
	lda FontBuf+0,x
	sta PF1		; set left score bitmap
	SLEEP 28
	lda FontBuf+5,x
	sta PF1		; set right score bitmap
	iny
	cpy #10
	bcc ScanLoop1a

	; Clear the playfield
	lda #0
	sta WSYNC
	sta PF1
	rts

; Fetches bitmap data for two digits of a
; BCD-encoded number, storing it in addresses
; FontBuf+x to FontBuf+4+x.
GetBCDBitmap subroutine
; First fetch the bytes for the 1st digit
	pha		; save original BCD number
        and #$0F	; mask out the least significant digit
        sta Temp
        asl
        asl
        adc Temp	; multiply by 5
        tay		; -> Y
        lda #5
        sta Temp	; count down from 5
.loop1
        lda DigitsBitmap,y
        and #$0F	; mask out leftmost digit
        sta FontBuf,x	; store leftmost digit
        iny
        inx
        dec Temp
        bne .loop1
; Now do the 2nd digit
        pla		; restore original BCD number
        lsr
        lsr
        lsr
        lsr		; shift right by 4 (in BCD, divide by 10)
        sta Temp
        asl
        asl
        adc Temp	; multiply by 5
        tay		; -> Y
        dex
        dex
        dex
        dex
        dex		; subtract 5 from X (reset to original)
        lda #5
        sta Temp	; count down from 5
.loop2
        lda DigitsBitmap,y
        and #$F0	; mask out leftmost digit
        ora FontBuf,x	; combine left and right digits
        sta FontBuf,x	; store combined digits
        iny
        inx
        dec Temp
        bne .loop2
	rts

	org $FF00

;;; Playfield data for cards

; Before game starts
PFData0
        .byte #%11100000

PFData1
        .byte #%11111000

PFData2
        .byte #%00000000

; For flipped cards

PFDataFlipped1
        .byte #%11111001


; For flipped cards, top/bottom

PFDataFlippedEnd2
        .byte #%01111111

; For flipped cards, middle
PFDataFlippedMiddle2
        .byte #%01000000

; Bitmap pattern for digits
DigitsBitmap
	.byte $0E ; |    XXX |
	.byte $0A ; |    X X |
	.byte $0A ; |    X X |
	.byte $0A ; |    X X |
	.byte $0E ; |    XXX |
	
	.byte $22 ; |  X   X | 
	.byte $22 ; |  X   X | 
	.byte $22 ; |  X   X | 
	.byte $22 ; |  X   X | 
	.byte $22 ; |  X   X | 
	
	.byte $EE ; |XXX XXX | 
	.byte $22 ; |  X   X | 
	.byte $EE ; |XXX XXX | 
	.byte $88 ; |X   X   | 
	.byte $EE ; |XXX XXX | 
	
	.byte $EE ; |XXX XXX | 
	.byte $22 ; |  X   X | 
	.byte $66 ; | XX  XX | 
	.byte $22 ; |  X   X | 
	.byte $EE ; |XXX XXX | 

	.byte $AA ; |X X X X | 
	.byte $AA ; |X X X X | 
	.byte $EE ; |XXX XXX | 
	.byte $22 ; |  X   X | 
	.byte $22 ; |  X   X | 

	.byte $EE ; |XXX XXX | 
	.byte $88 ; |X   X   | 
	.byte $EE ; |XXX XXX | 
	.byte $22 ; |  X   X | 
	.byte $EE ; |XXX XXX | 
	
	.byte $EE ; |XXX XXX | 
	.byte $88 ; |X   X   | 
	.byte $EE ; |XXX XXX | 
	.byte $AA ; |X X X X | 
	.byte $EE ; |XXX XXX | 
	
	.byte $EE ; |XXX XXX | 
	.byte $22 ; |  X   X | 
	.byte $22 ; |  X   X | 
	.byte $22 ; |  X   X | 
	.byte $22 ; |  X   X | 
	
	.byte $EE ; |XXX XXX | 
	.byte $AA ; |X X X X | 
	.byte $EE ; |XXX XXX | 
	.byte $AA ; |X X X X | 
	.byte $EE ; |XXX XXX | 
	
	.byte $EE ; |XXX XXX | 
	.byte $AA ; |X X X X | 
	.byte $EE ; |XXX XXX | 
	.byte $22 ; |  X   X | 
	.byte $EE ; |XXX XXX | 	

;---Graphics Data from PlayerPal 2600---

SuitSpritesIndex
	; not efficient use of space, but easy way to calculate the offset
	; into SuitSprites needed for each suit
	.byte #$0
	.byte #$8
	.byte #$10
	.byte #$18

SuitSprites
        .byte #%00000000;-- diamond
        .byte #%00001000;--
        .byte #%00011100;--
        .byte #%00111110;--
        .byte #%00011100;--
        .byte #%00001000;--
        .byte #%00000000;--
        .byte #%00000000;--

        .byte #%00011000;-- ; heart
        .byte #%00111100;--
        .byte #%01111110;--
        .byte #%11111111;--
        .byte #%11111111;--
        .byte #%11111111;--
        .byte #%01100110;--
        .byte #%00000000;--

		.byte #%00011000;--; club
        .byte #%00011000;--
        .byte #%01011010;--
        .byte #%11111111;--
        .byte #%01011010;--
        .byte #%00011000;--
        .byte #%00111100;--
        .byte #%00011000;--

		.byte #%00011100;--; spade	
        .byte #%00011100;--
        .byte #%00111110;--
        .byte #%01111111;--
        .byte #%01111111;--
        .byte #%00111110;--
        .byte #%00011100;--
        .byte #%00001000;--

CardSpritesIndex
	; not efficient use of space, but easy way to calculate the offset
	; into CardSprites needed for each suit
	.byte #0   ; 1
	.byte #8   ; 2
	.byte #16  ; 3
	.byte #24  ; 4
	.byte #32  ; 5
	.byte #40  ; 6
	.byte #48  ; 7
	.byte #56  ; 8
	.byte #64  ; 9
	.byte #72  ; 10
	.byte #80  ; J
	.byte #88  ; Q
	.byte #96  ; K
	.byte #104  ; A

CardSprites
		.byte #%00111000;-- 1
        .byte #%00010000;--
        .byte #%00010000;--
        .byte #%00010000;--
        .byte #%00010000;--
        .byte #%00010000;--
        .byte #%00110000;--
        .byte #%00010000;--

		.byte #%00111100;-- 2
        .byte #%00110000;--
        .byte #%00011000;--
        .byte #%00001100;--
        .byte #%00000100;--
        .byte #%00100100;--
        .byte #%00100100;--
        .byte #%00011100;--

		.byte #%00111100;-- 3
        .byte #%00000100;--
        .byte #%00000100;--
        .byte #%00111100;--
        .byte #%00000100;--
        .byte #%00000100;--
        .byte #%00111100;--
        .byte #%00000000;--

		.byte #%00000100;-- 4
        .byte #%00000100;--
        .byte #%00000100;--
        .byte #%00111110;--
        .byte #%00100100;--
        .byte #%00010100;--
        .byte #%00001100;--
        .byte #%00000100;--

		.byte #%00111100;-- 5
        .byte #%00000100;--
        .byte #%00000100;--
        .byte #%00000100;--
        .byte #%00111100;--
        .byte #%00100000;--
        .byte #%00100000;--
        .byte #%00111100;--

		.byte #%00011000;-- 6
        .byte #%00100100;--
        .byte #%00100100;--
        .byte #%00111100;--
        .byte #%00100000;--
        .byte #%00100000;--
        .byte #%00011000;--
        .byte #%00000000;--

		.byte #%00100000;-- 7
        .byte #%00100000;--
        .byte #%00010000;--
        .byte #%00010000;--
        .byte #%00001000;--
        .byte #%00001000;--
        .byte #%00000100;--
        .byte #%00111100;--

		.byte #%00111000;-- 8
        .byte #%01000100;--
        .byte #%01000100;--
        .byte #%00111000;--
        .byte #%01000100;--
        .byte #%01000100;--
        .byte #%01000100;--
        .byte #%00111000;--

		.byte #%00000100;-- 9
        .byte #%00000100;--
        .byte #%00000100;--
        .byte #%00111100;--
        .byte #%01000100;--
        .byte #%01000100;--
        .byte #%01000100;--
        .byte #%00111000;--

		.byte #%01001100;-- 10
        .byte #%01010010;--
        .byte #%01010010;--
        .byte #%01010010;--
        .byte #%01010010;--
        .byte #%01010010;--
        .byte #%01010010;--
        .byte #%01001100;--

		.byte #%01110000;-- J
        .byte #%00010000;--
        .byte #%00010000;--
        .byte #%00010000;--
        .byte #%00010000;--
        .byte #%00010000;--
        .byte #%00010000;--
        .byte #%00111000;--

 		.byte #%00000000;-- Q
        .byte #%00111110;--
        .byte #%01000100;--
        .byte #%01000100;--
        .byte #%01000100;--
        .byte #%01000100;--
        .byte #%01000100;--
        .byte #%00111000;--

 		.byte #%00100100;-- K
        .byte #%00100100;--
        .byte #%00101000;--
        .byte #%00110000;--
        .byte #%00101000;--
        .byte #%00100100;--
        .byte #%00100100;--
        .byte #%00100100;--		

        .byte #%00000000;-- A
        .byte #%01000010;--
        .byte #%01000010;--
        .byte #%01111110;--
        .byte #%01000010;--
        .byte #%01000010;--
        .byte #%01000010;--
        .byte #%00100100;--
        .byte #%00011000;--
        .byte #%00000000;--
;---End Graphics Data---


; Epilogue
	org $fffc

	.word Start
	.word Start