        processor 6502
        include "vcs.h"
        include "macro.h"

;;;;; An Atari 2600 game! See http://8bitworkshop.com/
;;;;; PlayerPal 2600 (http://www.alienbill.com/2600/playerpalnext.html and http://alienbill.com/2600/playfieldpal.html)
;;;;; Making Games for the Atari 2600 by Steven Hugg

;;;;; Todos!
;;; fix "tearing"
;;; add "prize" on map
;;; can capture prize by touching prize
;;; show text on prize capture
;;; multiple maps 
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
PF_tmpX                  .byte
PF_tmpY                  .byte
PF_tmpA                  .byte
PF_wait_counter          .byte
PF_frame_counter          .byte

PLAYER_START_X  equ #7
PLAYER_START_Y  equ #164
PLAYER_SPRITE   equ #$FF   ; Sprite (1 line) for our ball
PLAYER_COLOR    equ #$60 ; Color for ball
PLAYER_SPRITE_HEIGHT equ #8 ; this is really 1 less than the sprite height
PLAYFIELD_BLOCK_HEIGHT equ #8
PLAYFIELD_ROWS equ #22

MAX_Y equ #167 ; Must be 192 - scoreboard - border - 2 (buffer, unclear why)
MIN_Y equ #17  ; Must be border height + sprite height + 1 (buffer, unclear why)

BORDER_COLOR equ #$51 ; last bit has to be 1 to do playfield reflection

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
        sta Player_X_Tmp
        lda #PLAYER_START_Y
        sta Player_Y
        sta Player_Y_Tmp

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
        ; Check joysticks
        jsr CheckJoystick
        sta WSYNC ; this will commit to 1 scanline
        lda #0
        sta COLUPF
        lda #0
        sta PF_wait_counter
        sta PF_frame_counter
        lda #01
        sta CTRLPF

        jsr PositionPlayerX ; 2 scanlines
        ldx #33 
PreLoop dex
        sta WSYNC
        bne PreLoop
        
;;
;; 192 lines of frame total
;;
Drawing
        ;; We will use y to track our current scanline. 
        ldy #192
        ; Draw  
        lda #BORDER_COLOR 
        sta COLUPF
        lda #$00 
        sta PF0
        sta PF1
        sta PF2

; Loop until we hit the vertical position we want for the player. 
        ; This first part makes sure the sprite doesn't move past the boundary. Collision detection
        ; should be catching this but there's a line where it does not. This should be refactored.      
VLoop   jsr DrawPlayfield
        dey
        sta WSYNC
        cpy Player_Y
        bne VLoop

; Draw the player sprite
SkipVLoop
        ; Setup for sprite drawing
        ldx #PLAYER_SPRITE_HEIGHT  ; sprite data index
SpriteLoop
        jsr DrawPlayfield
        lda PLAYER_SPRITE_DATA,x
        sta GRP0
        lda PLAYER_COLOR_DATA,x
        sta COLUP0
        sta WSYNC
        dey ; track scanlines
        dex
        bne SpriteLoop
       
        ; Loop until we are at BORDER_HEIGHT, meaning all scan lines processed except for the bottom
VWait   jsr DrawPlayfield
        dey
        sta WSYNC
        bne VWait
        
        lda #0
        sta PF0
        sta PF1
        sta PF2
     
; 30 lines of overscan
        ldx #30
        clc
PostLoop 
        dex
        sta WSYNC
        bne PostLoop

; go to next frame
        nop
        jmp NextFrame

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Subroutines
;;;

DrawPlayfield
        ; preserve/restore values
        sta PF_tmpA
        stx PF_tmpX
        sty PF_tmpY

        ; If we've run through all our frames, stop drawing
        ldy PF_frame_counter
        cpy #PLAYFIELD_ROWS
        beq .RestoreAndReturn

        ldx PF_wait_counter
        bne .StillWaiting
.NewFrame
        ; Set playfield
        lda PFData0,y
        sta PF0
        lda PFData1,y
        sta PF1
        lda PFData2,y
        sta PF2

        ; Move to next increment and checkor wrap
        ldx #PLAYFIELD_BLOCK_HEIGHT
        iny
        jmp .PlayfieldDone
.StillWaiting
        dex
.PlayfieldDone
        stx PF_wait_counter
        sty PF_frame_counter
.RestoreAndReturn
        lda PF_tmpA
        ldX PF_tmpX
        ldy PF_tmpY
        rts


; Handle the (very timing dependent) adjustment of X position for the player
PositionPlayerX
        lda Player_X
        sec
        sta WSYNC
        sta HMCLR ; Clear old horizontal pos

        ; Divide the X position by 15, the # of TIA color clocks per loop
DivideLoop
        sbc #15
        bcs DivideLoop

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
        ; First do any collision checks
        bit CXP0FB ; Player 0/Playfield
        bpl .NoCollision
        ldx Player_X_Tmp
        stx Player_X
        ldx Player_Y_Tmp
        stx Player_Y
.NoCollision
        ldx Player_X
        stx Player_X_Tmp ; Store so we can restore on collsion
        lda SWCHA
        and #$80 ; 1000000
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
.TestDown
        lda SWCHA
        and #$10 ; 00010000
        beq .Done ; checks bit 4 set
        cpx #MIN_Y
        beq .Done
        dex
.Done
        stx Player_Y
        sta CXCLR ; clear collision checks

        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Sprite data
;---Graphics Data from PlayerPal 2600---

PLAYER_SPRITE_DATA
        .byte #%00000000;$30m
        .byte #%00000000;$30m
        .byte #%00110000;$30
        .byte #%00000000;$30
        .byte #%00000000;$30
        .byte #%00110000;$30
        .byte #%00110000;$30
        .byte #%00110000;$30
        .byte #%00110000;$30
        .byte #%00110000;$30
        .byte #%00000000;$30m
;---End Graphics Data---


;---Color Data from PlayerPal 2600---

PLAYER_COLOR_DATA
        .byte #$1A;
        .byte #$1A;
        .byte #$1A;
        .byte #$1A;
        .byte #$1A;
        .byte #$1A;
        .byte #$1A;
        .byte #$1A;
        .byte #$1A;
        .byte #$1A;
;---End Color Data---

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PFData0
        .byte #%00000000
        .byte #%00000000
        .byte #%11110000
        .byte #%10010000
        .byte #%01010000
        .byte #%01010000
        .byte #%01010000
        .byte #%01010000
        .byte #%11010000
        .byte #%00010000
        .byte #%00010000
        .byte #%11010000
        .byte #%01010000
        .byte #%01010000
        .byte #%00010000
        .byte #%01010000
        .byte #%01010000
        .byte #%11110000
        .byte #%00000000
        .byte #%00000000
        .byte #%00000000
        .byte #%00000000
PFData1
        .byte #%00000000
        .byte #%00000000
        .byte #%11111111
        .byte #%10100000
        .byte #%10101111
        .byte #%00101000
        .byte #%10111111
        .byte #%10000000
        .byte #%10111111
        .byte #%00100001
        .byte #%00101111
        .byte #%10101000
        .byte #%10101011
        .byte #%10101000
        .byte #%10101010
        .byte #%11101000
        .byte #%00001010
        .byte #%11111111
        .byte #%00000000
        .byte #%00000000
        .byte #%00000000
        .byte #%00000000

PFData2
        .byte #%00000000
        .byte #%00000000
        .byte #%11111111
        .byte #%00000000
        .byte #%11111100
        .byte #%00000000
        .byte #%01111111
        .byte #%01000000
        .byte #%01111110
        .byte #%01000010
        .byte #%01111010
        .byte #%00000000
        .byte #%11101111
        .byte #%00100001
        .byte #%01111011
        .byte #%00100001
        .byte #%10001011
        .byte #%11111111
        .byte #%00000000
        .byte #%00000000
        .byte #%00000000
        .byte #%00000000








; Epilogue

        org $fffc
        .word Start     ; reset vector
        .word Start     ; BRK vector
