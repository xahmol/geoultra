; Text input: GetString, InitTextPrompt, PromptOn, PromptOff and the
; blinking prompt at interrupt level. Written from the HG2G2022
; descriptions; behaviour details (the default text, the keys that
; delete, the margin fault, the prompt's blink counter in alphaFlag and
; its sprite) follow the reassembled GEOS 2.0 kernal, mist64/geos
; kernal/conio/conio4.s and conio5.s, read as behaviour reference only.
; Own code; checked with tests/conformance/getstring.py.

        .include "geos.inc"
        .include "hw.inc"

        .export GetString, InitTextPrompt, PromptOn, PromptOff, PromptTick
        .import PutString, PutChar, DeleteChar, PosSprite, EnablSprite
        .import DisablSprite

PROMPT_DELAY    = 60            ; frames between blinks
stringX         = $84BE         ; word
stringY         = $84C0
PROMPT_PIC      = SPRITE_PICS + 64

        .segment "KSTATE"               ; saved and restored by dialog boxes

stringLen:      .byte 0
stringMaxLen:   .byte 0
stringMargCtrl: .byte 0
tmpKeyVector:   .word 0

        .segment "CODE"

; GetString: r0 = buffer (default text, NULL-terminated), r1L = $80 for
; the fault routine in r4, r2L = maximum length, r11 = x, r1H = y of the
; top of the characters. keyVector = routine called after RETURN (with
; X = length). Returns at once; the input runs from MainLoop.
; Destroys A, X, Y, r0-r13.
GetString:
        lda r0L
        sta string
        lda r0H
        sta string+1
        lda r1L
        sta stringMargCtrl
        lda r1H
        sta stringY
        lda r2L
        sta stringMaxLen
        lda r1H                 ; the default text on the baseline
        pha
        clc
        adc baselineOffset
        sta r1H
        jsr PutString
        pla
        sta r1H
        sec                     ; length = end of the default text
        lda r0L
        sbc string
        sta stringLen
        lda r11L
        sta stringX
        lda r11H
        sta stringX+1
        lda keyVector
        sta tmpKeyVector
        lda keyVector+1
        sta tmpKeyVector+1
        lda #<StringKey
        sta keyVector
        lda #>StringKey
        sta keyVector+1
        lda #<StringFault
        sta StringFaultVec
        lda #>StringFault
        sta StringFaultVec+1
        bit stringMargCtrl
        bpl @prompt
        lda r4L
        sta StringFaultVec
        lda r4H
        sta StringFaultVec+1
@prompt:
        lda curHeight
        jsr InitTextPrompt
        jmp PromptOn

; Default fault routine: the buffer is full at this length (the character
; that did not fit is dropped).
StringFault:
        lda stringLen
        sta stringMaxLen
        dec stringLen
        rts

; keyVector during input: one key in keyData.
StringKey:
        jsr PromptOff
        lda stringX
        sta r11L
        lda stringX+1
        sta r11H
        lda stringY
        sta r1H
        ldy stringLen
        lda keyData
        bmi @end                ; shortcuts: ignored (prompt stays off)
        cmp #CR
        beq Done
        cmp #BACKSPACE
        beq @delete
        cmp #KEY_DELETE
        beq @delete
        cmp #KEY_INSERT
        beq @delete
        cmp #KEY_RIGHT
        beq @delete
        cmp #' '
        bcc @end                ; other control keys: ignored
        cpy stringMaxLen
        beq @on                 ; buffer full
        sta (string),y
        lda r1H
        clc
        adc baselineOffset
        sta r1H
        lda (string),y
        jsr PutChar
        inc stringLen
        jsr SaveX
@on:    jmp PromptOn
@delete:
        cpy #0
        beq @on
        dey
        sty stringLen
        lda r1H
        clc
        adc baselineOffset
        sta r1H
        lda (string),y
        jsr DeleteChar
        jsr SaveX
        jmp PromptOn
@end:   rts

SaveX:  lda r11L
        sta stringX
        lda r11H
        sta stringX+1
        rts

; RETURN: end the string, restore the vectors, call the routine that
; keyVector held (X = length).
Done:   php
        sei
        jsr PromptOff
        lda alphaFlag
        and #$7F
        sta alphaFlag
        plp
        lda #0
        sta (string),y
        lda tmpKeyVector
        sta r0L
        lda tmpKeyVector+1
        sta r0H
        lda #0
        sta keyVector
        sta keyVector+1
        sta StringFaultVec
        sta StringFaultVec+1
        ldx stringLen
        lda r0L
        ora r0H
        beq @none
        jmp (r0)
@none:  rts

; PromptOn: show the prompt (sprite 1) at stringX/stringY.
; Destroys A, X, r3L.
PromptOn:
        lda alphaFlag
        ora #$40
        sta alphaFlag
        lda #1
        sta r3L
        lda stringX
        sta r4L
        lda stringX+1
        sta r4H
        lda stringY
        sta r5L
        jsr PosSprite
        jsr EnablSprite
        jmp Rearm

; PromptOff: hide the prompt. Destroys A, X, r3L.
PromptOff:
        lda alphaFlag
        and #<~$40
        sta alphaFlag
        lda #1
        sta r3L
        jsr DisablSprite
Rearm:  lda alphaFlag           ; blink counter back to PROMPT_DELAY
        and #$C0
        ora #PROMPT_DELAY
        sta alphaFlag
        rts

; InitTextPrompt: A = height. Sprite 1 becomes a one-pixel vertical line
; of height + 1 rows, as GEOS 2.0 draws it (double height above 21
; lines, at most 42) in the pointer's colour. Destroys A, X, Y.
InitTextPrompt:
        tay
        php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda vicSpr0Color
        sta vicSpr0Color+1
        lda $D017               ; no double height yet
        and #$FD
        sta $D017
        lda #%10000011
        sta alphaFlag
        ldx #63
        lda #0
@clear: sta PROMPT_PIC,x
        dex
        bpl @clear
        cpy #43
        bcc @max
        ldy #42
@max:   cpy #22
        bcc @line
        tya                     ; above 21 lines: half, double height
        lsr
        tay
        lda $D017
        ora #$02
        sta $D017
@line:  ldx #0                  ; height + 1 rows (as GEOS 2.0)
        lda #$80
@draw:  sta PROMPT_PIC,x
        inx
        inx
        inx
        dey
        bpl @draw
        pla
        sta CPU_PORT
        plp
        rts

; Interrupt level: blink the prompt while input is active (alphaFlag bit
; 7), toggling every PROMPT_DELAY frames.
PromptTick:
        lda alphaFlag
        bpl @end
        dec alphaFlag
        lda alphaFlag
        and #$3F
        bne @end
        bit alphaFlag
        bvc @on
        jmp PromptOff
@on:    jmp PromptOn
@end:   rts
