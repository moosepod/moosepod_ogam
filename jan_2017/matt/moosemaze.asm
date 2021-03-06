        processor 6502
        include "vcs.h"
        include "macro.h"

;;;;; An Atari 2600 game! See http://8bitworkshop.com/
;;;;; PlayerPal 2600 (http://www.alienbill.com/2600/playerpalnext.html and http://alienbill.com/2600/playfieldpal.html)
;;;;; Making Games for the Atari 2600 by Steven Hugg

;;;;; MooseMaze is barely a game. It's something I built for the "one game a month" project.
;;;;; There's a maze. You can navigate it. That's it.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables segment

        seg.u Variables
        org $80

PLAYER_START_X  equ #$15
PLAYER_START_Y  equ #166 ; needs to be even

CurrentLine             .byte
Player_X                .byte ; X position of ball sprint
Player_Y                .byte ; Y position of player sprite. 
Player_X_Tmp            .byte 
Player_Y_Tmp            .byte 

; Pointers for current playfields
PF1_Pointer             .word
PF2_Pointer             .word
PF4_Pointer             .word
PF5_Pointer             .word

BORDER_COLOR equ #$A8 
BACKGROUND_COLOR equ #$76
PLAYER_COLOR equ #$DE
MAX_Y equ #173
MIN_Y equ #0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Code segment

        seg Code
        org $f000

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Setup
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Start
        CLEAN_START

Initialize
        lda #PLAYER_START_X
        sta Player_X
        lda #PLAYER_START_Y
        sta Player_Y
		lda #1
		sta CTRLPF
        lda #BACKGROUND_COLOR
        sta COLUBK

NextFrame
; Enable VBLANK (disable output)
    lda #2
        sta VBLANK
; At the beginning of the frame we set the VSYNC bit...
    lda #2
    sta VSYNC
; And hold it on for 3 scanlines...
    sta WSYNC
;sta WSYNC
    sta WSYNC
; Now we turn VSYNC off.
    lda #0
    sta VSYNC
;;
;; 37 lines of underscan total
;;

        ; Check joysticks. This will use 2 scanlines in total
        sta WSYNC ; Give our joystick check a full scanline
        jsr CheckJoystick

        ; Clear sprite , then position sprite on X
        lda #00
        sta GRP0

        ; Clear playfield
        lda #$00
        sta PF0
        sta PF1
        sta PF2

        ; Setup current map
        lda #<PFData1
        sta PF1_Pointer ; store lo byte
        lda #>PFData1
        sta PF1_Pointer+1 ; store hi byte

        lda #<PFData2
        sta PF2_Pointer ; store lo byte
        lda #>PFData2
        sta PF2_Pointer+1 ; store hi byte

        lda #<PFData4
        sta PF4_Pointer ; store lo byte
        lda #>PFData4
        sta PF4_Pointer+1 ; store hi byte

        lda #<PFData5
        sta PF5_Pointer ; store lo byte
        lda #>PFData5
        sta PF5_Pointer+1 ; store hi byte

        jsr PositionPlayerX ; 2 scanlines
    
		ldx #32
UnderscanExtraLoop dex
        sta WSYNC
        bne UnderscanExtraLoop

        lda #BORDER_COLOR 
        sta COLUPF

        ; Re-enable output (disable VBLANK)
        lda #0
        sta VBLANK

        ; Setup for start of kernel
        lda #174 ; number of lines in main loop - buffer at top - 2 line buffer
        sta CurrentLine


        ldx #$9
PreLoop
        dex
        sta WSYNC
        bne PreLoop

		; We store the current line (0 being the bottom of the screen)
Kernel
		;; We have a two line kernel. First line sets the playfield,
		;; then swaps to alternative playfield, then swaps back
		;; 
		;; We have 24 lines of playfield total and increment the counter every 8
		
		; cycle until we hit the right spot to switch playfields and back
		sta WSYNC
		lsr
		lsr
		lsr ; 3 lsr = Divide by 8 to get our index 
		tay

		; Draw playfield        
        lda #$C0
        sta PF0
        lda (PF1_Pointer),y
        sta PF1
        lda (PF2_Pointer),y
        sta PF2

		nop
		nop
		nop
		nop
		nop
		nop

        ; Immediately switch to second playfield
        lda (PF5_Pointer),y
        sta PF2
        lda (PF4_Pointer),y
        sta PF1

       	; And back       
        lda (PF2_Pointer),y
        sta PF2
        lda (PF1_Pointer),y
        sta PF1

		sta WSYNC

		; Line 2 of kernel

		; Need to draw alternate playfield after exactly 21 cycles
         lda CurrentLine ; 3 cycles
         cmp Player_Y ; 2 cycles
         bne NoPlayer ; 2 cycles if fall through, 3 if taken
         lda #PLAYER_COLOR ; 2 cycles
         sta COLUP0 ; 3 cycles
         lda #$C0 ; 2 cycles
         sta GRP0 ; 3 cycles
         jmp SecondPlayfield ; 3 cycles
NoPlayer
        lda #$00 ; 2 cycles
        sta COLUP0 ; 3 cycles
        lda #$00 ; 2 cycles
        sta GRP0 ; 3 cycles
        nop
SecondPlayfield
        nop
        nop
        nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop

		; Switch to second playfield
        lda (PF5_Pointer),y
        sta PF2
        lda (PF4_Pointer),y
        sta PF1

		ldy CurrentLine	
		dey
		dey

		sty CurrentLine

		; Calculate our y index for the next playfield
		tya
		bne Kernel ; the lsr should set the Z flag

;; 
;;      Space at bottom
;;
        sta WSYNC
        lda #$00
        sta PF0
        sta PF1
        sta PF2
        ldx #$9
EndLoop
        dex
        sta WSYNC
        bne EndLoop
;;      
;; 30 lines of overscan
;;
		lda #0
        sta PF0
        sta PF1
        sta PF2

		ldx #30
PostLoop
        dex
        sta WSYNC
        bne PostLoop

        jmp NextFrame

; Handle the (very timing dependent) adjustment of X position for the player
PositionPlayerX
        lda Player_X
        sec
        sta WSYNC
        sta HMCLR ; Clear old horizontal pos

        ; Divide the X position by 15, the # of TIA color clocks per loop
DivideLoopX
        sbc #15
        bcs DivideLoopX

        ; A will contain remainder of division. Convert to fine adjust
        ; which is -7 to +8
        eor #7  ; calcs (23-A) % 16
        asl
        asl
        asl
        asl
        sta HMP0                ; set the fine position

        sta RESP0               ; set the coarse position

        sta WSYNC
        sta HMOVE               ; set the fine positioning

        rts

; This subroutine checks the player one joystick and moves the player accordingly
CheckJoystick
        ; First do any collision checks. Check player 0 with playfield (bit 1)
        bit CXP0FB ; Player 0/Playfield
        bpl .NoCollision
        jmp .ResetPlayerPos
.NoCollision
        ldx Player_X
        stx Player_X_Tmp ; Store so we can restore on collsion
        lda SWCHA
        and #$80 ; 1000000
        sta WSYNC ; make time for rest of logic
        beq .TestRight  ; checks bit 7 set
        dex 
.TestRight
        lda SWCHA
        and #$40 ; 0100000
        beq .TestUp ; checks bit 6 set
        inx
.TestUp
        stx Player_X        
        ; Now we repeat the process but with a SWCHA that is shifted left twice, so down is 
        ; bit 7 and up is bit 6
        ldx Player_Y
        stx Player_Y_Tmp ; Store so we can restore on collsion
        lda SWCHA
        and #$20 ; 00100000
        beq .TestDown  ; checks bit 5 set
        ; We need to do an explicit range check on Player_Y or the drawing kernel gets thrown off
        ; and collisions with border don't trigger properly
        cpx #MAX_Y
        beq .Done
        inx   
        inx ; we move in units of 2 Y positions to match kernel
.TestDown
        lda SWCHA
        and #$10 ; 00010000
        beq .Done ; checks bit 4 set
        cpx #MIN_Y
        beq .Done
        dex
        dex ; we move in units of 2 Y positions to match kernel
        jmp .Done
.ResetPlayerPos
        sta WSYNC ; mirror WSYNC with non-collsion logic
        ldx Player_X_Tmp
        stx Player_X
        ldx Player_Y_Tmp
        stx Player_Y
.Done
        stx Player_Y
        sta CXCLR ; clear collision checks
.JoystickReturn
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; This file will be merged by make with the map data (map.asm) and the footer (footer.asm)
;;; So edit main.asm then use make
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    align $100; make sure data doesn't cross page boundary

PFData1
 .byte #%11111111
 .byte #%11111111
 .byte #%10000000
 .byte #%10101011
 .byte #%10101010
 .byte #%10101010
 .byte #%10101010
 .byte #%11101010
 .byte #%10001010
 .byte #%10111110
 .byte #%10100000
 .byte #%10101111
 .byte #%10001000
 .byte #%10111010
 .byte #%10000010
 .byte #%11111111
 .byte #%10000000
 .byte #%10111111
 .byte #%10001000
 .byte #%11101011
 .byte #%10001000
 .byte #%11111111
 .byte #%11111111

PFData2
 .byte #%11111111
 .byte #%11111111
 .byte #%00000100
 .byte #%11110111
 .byte #%00010100
 .byte #%01010101
 .byte #%01000101
 .byte #%01111101
 .byte #%00000001
 .byte #%01111111
 .byte #%01000101
 .byte #%11010101
 .byte #%01010100
 .byte #%01010111
 .byte #%00010001
 .byte #%11111101
 .byte #%00000100
 .byte #%11010111
 .byte #%00010000
 .byte #%11111111
 .byte #%00000000
 .byte #%11111111
 .byte #%11111111

PFData5
 .byte #%11111111
 .byte #%11111111
 .byte #%00000000
 .byte #%10111110
 .byte #%10100000
 .byte #%10111111
 .byte #%10000010
 .byte #%10111010
 .byte #%10001000
 .byte #%11111011
 .byte #%10001000
 .byte #%10101111
 .byte #%00101000
 .byte #%11101010
 .byte #%10001010
 .byte #%10111010
 .byte #%10001010
 .byte #%11101011
 .byte #%00100010
 .byte #%10111110
 .byte #%10000000
 .byte #%11111111
 .byte #%11111111

PFData4
 .byte #%11111111
 .byte #%11111111
 .byte #%00000001
 .byte #%01111101
 .byte #%01000100
 .byte #%01110111
 .byte #%00000100
 .byte #%11110101
 .byte #%00000101
 .byte #%01111101
 .byte #%00010001
 .byte #%11010101
 .byte #%00010101
 .byte #%11110101
 .byte #%00010101
 .byte #%01010111
 .byte #%01000100
 .byte #%01111101
 .byte #%00000001
 .byte #%01111111
 .byte #%00000000
 .byte #%11111111
 .byte #%11111111

; Epilogue

        org $fffc
        .word Start     ; reset vector
        .word Start     ; BRK vector
