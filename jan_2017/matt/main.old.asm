        processor 6502
        include "vcs.h"
        include "macro.h"

;;;;; An Atari 2600 game! See http://8bitworkshop.com/
;;;;; PlayerPal 2600 (http://www.alienbill.com/2600/playerpalnext.html and http://alienbill.com/2600/playfieldpal.html)
;;;;; Making Games for the Atari 2600 by Steven Hugg

;;;;; FriendShip is an Atari 2600 game built as part of One Game A Month (http://www.onegameamonth.com/)
;;;;; It is primarily a project to learn how to develop 2600 games in assembly language, so is very tech driven.
;;;;; In addition I wanted to grapple with some of the challenges, so the game kernel is my own (and not one of the certainly better
;;;;; ones available)
;;;;;
;;;;; Basic concept: you sail your ship using the joystick (plugged into left joystick port)
;;;;; You'll be blocked by yellow sandbars. 
;;;;; Your goal is to reach the other ship, your friend ship
;;;;; You can exit through various points to go to the next set of mazes
;;;;;
;;;;; Architecture
;;;;; The main ship is just the player 0
;;;;; The primary maze is drawn through reflected playfields
;;;;; Additional walls are put in place to make it asynchronous using an async playfield

;;;;; Todos!
;;;;; Add exits along bottom explicity configured (top as well?). 
;;;;; Hook up maze A with maze B. When ship touches bottom of screen, transfer to next screen. Transfer is stored by X and Y
;;;;; Will need to compress mazes somehow. Current structure is 768 bytes per maze, which uses up 3k just for 4 mazes...
;;;;; i think if we bit shift to double/half y we'll still have enough cycles and can halve the memory.

;;; CONCEPT:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Variables segment

        seg.u Variables
        org $80

Temp                    .byte
Player_X                .byte ; X position of ball sprint
Player_Y                .byte ; Y position of player sprite. 
                              ; Note Y-positions are measured from _bottom_ of screen and increase going up

Player_X_Tmp            .byte 
Player_Y_Tmp            .byte 

; For drawing playfield
PF_frame_counter          .byte

PLAYER_START_X  equ #8
PLAYER_START_Y  equ #170 ; needs to be odd
PLAYER_SPRITE   equ #$FF   ; Sprite (1 line) for our ball
PLAYER_COLOR    equ #$60 ; Color for ball
PLAYER_SPRITE_HEIGHT equ #18 ; this is really 2ma greater than sprite height, there's a buffer empty line that clears the sprite
PLAYFIELD_BLOCK_HEIGHT equ #8
PLAYFIELD_ROWS equ #22

SCOREBOARD_HEIGHT equ #177 ; must be odd since compare is on odd lines
SCOREBOARD_BACKGROUND_COLOR equ #$00
PLAYFIELD_BACKGROUND_COLOR equ #$9E

MAX_Y equ #173
MIN_Y equ #16

BORDER_COLOR equ #$EF ; last bit has to be 1 to do playfield reflection


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
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Kernel        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

NextFrame
        lsr SWCHB       ; test Game Reset switch
        bcc Start       ; reset?

; 3 lines of VSYNC
        VERTICAL_SYNC

;;
;; 37 lines of underscan total
;;
        ; Check joysticks. This will use 2 scanlines in total
        sta WSYNC ; Give our joystick check a full scanline
        jsr CheckJoystick

        ; More Initialization past a fresh scanline
        sta WSYNC ; this will commit to 1 scanline
        lda #0
        sta COLUPF
        lda #0
        sta PF_frame_counter
        lda #01
        sta CTRLPF

        ; Clear sprite color and sprite
        lda #00
        sta GRP0

        jsr PositionPlayerX ; 2 scanlines

        ldx #28
PreLoop dex
        sta WSYNC
        bne PreLoop
        
SetupDrawing
        ;; We will use y to track our current scanline. 
        ldy #0
        sty PF_frame_counter
   
        ldy #192 ; one manual wsync 

        ; Setup header  
        lda #BORDER_COLOR 
        sta COLUPF
        lda #$00
        sta PF0
        sta PF1
        sta PF2

        ; Start background color for scoreboard
        lda #SCOREBOARD_BACKGROUND_COLOR
        sta COLUBK


        ; Complete last line of underscan
        sta WSYNC

;;
;; 192 lines of frame total     
;;



ScanLoop
        ; we expand our playfield data vertically into units 8 tall. Rather than
        ; test for mod 8 directly, we compare with a precalculated list of indexes

        ; Draw background        
        lda PFData0,y
        sta PF0
        lda PFData1,y
        sta PF1
        lda PFData2,y
        sta PF2
        
        ; Use nops to hit the pixel we want to swap playfield on
        nop 
        nop
        nop
        nop
        
        nop
        nop

        lda PFData3,y
        sta PF1

        ; Use nops to hit the pixel we want to swap playfield on
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop

        lda PFData1,y
        sta PF1

        sta WSYNC
        dey ; decrement main line counter

        ; Draw player sprite
        lda Player_Y
        sty Temp  ; store our current line count into a temp variable, then subtract it from sprite position
        sbc Temp  
        bmi UpdatePlayfieldNoSprite ; If the subtraction is negative, we are above (closer to top of screen) for this sprite
        
        ; Jump to end if we are past the end of the sprite
        tax
        cpx #PLAYER_SPRITE_HEIGHT
        bcs UpdatePlayfieldNoSprite

        ; Draw the current line of the sprite
        lda PLAYER_COLOR_DATA,x
        sta COLUP0
        lda Player_Sprite_Data,x
        sta GRP0
UpdatePlayfieldSprite
        ldx #2
        jmp UpdatePlayfieldLoop
UpdatePlayfieldNoSprite
        ldx #3
        jmp UpdatePlayfieldLoop
UpdatePlayfieldLoop
        ; x will have number of loops based on previous work on scanline
        ; to push cycle to point to switch playfield
        dex
        bne UpdatePlayfieldLoop

        ; Swap playfield bytes
        lda PFData3,y
        sta PF1

CheckScoreboard
        cpy #SCOREBOARD_HEIGHT
        bne ScanLoopEnd
        lda #PLAYFIELD_BACKGROUND_COLOR
        sta COLUBK
ScanLoopEnd
        sta WSYNC
        dey
        ; jump to start of loop if we have remaining lines
        bne ScanLoop

; 30 lines of overscan
; Clear background for remaining
OverscanCleanup
        lda #SCOREBOARD_BACKGROUND_COLOR
        sta COLUBK
        lda #00
        sta PF0
        sta PF1
        sta PF2
        ldx #30
PostLoop
        dex
        sta WSYNC
        bne PostLoop

        jmp NextFrame

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Subroutines
;;;

DrawSprite
    ;; Draw a given sprite. Note we assume all sprites are SPRITE_HEIGHT units high. This is double the rows of data
    ;; due to the two-line kernel. 
    ;; (!) This routine will blow out the X and A registers


.Return
    rts

DrawWallSprite

.Return2
    rts


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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Sprite data
;---Graphics Data from PlayerPal 2600---

; data lines are all doubled up to account for our two-line kernel. 
    align $100; make sure data doesn't cross page boundary

Player_Sprite_Data
        .byte #%00011000;$0C
        .byte #%00011000;$0C
        .byte #%00011100;$0C
        .byte #%00011100;$0C
        .byte #%00011110;$0C
        .byte #%00011110;$0C
        .byte #%00010000;$0C
        .byte #%00010000;$0C
        .byte #%00010000;$0C
        .byte #%00010000;$0C
        .byte #%01111110;$F4
        .byte #%01111110;$F4
        .byte #%01111110;$F4
        .byte #%01111110;$F4
        .byte #%00111100;$F4
        .byte #%00111100;$F4
        .byte #%00000000 ; blank line to offset sprite (we never reach 0)
        .byte #%00000000 ; buffer line that clears sprite on last line
        .byte #%00000000 ; blank line to offset sprite (we never reach 0)
        .byte #%00000000 ; buffer line that clears sprite on last line
;---End Graphics Data---

;---Color Data from PlayerPal 2600---

; color lines are doubled up to account for our two line kernel.
PLAYER_COLOR_DATA
        .byte #$0C;
        .byte #$0C;
        .byte #$0C;
        .byte #$0C;
        .byte #$0C;
        .byte #$0C;
        .byte #$0C;
        .byte #$0C;
        .byte #$0C;
        .byte #$0C;
        .byte #$F4;
        .byte #$F4;
        .byte #$F4;
        .byte #$F4;
        .byte #$F4;
        .byte #$F4;
        .byte #$F4;
        .byte #$F4;
        .byte #$F4;
        .byte #$F4;
;---End Color Data---

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; This file will be merged by make with the map data (map.asm) and the footer (footer.asm)
;;; So edit main.asm then use make
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;