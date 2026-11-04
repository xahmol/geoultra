; Keyboard: matrix scan at interrupt level, key repeat, a 16-key queue,
; and GetNextChar. Key codes from HG2G2022 (ASCII plus the KEY_ codes in
; geos.inc); the C64 key matrix is the hardware's.

        .include "geos.inc"
        .include "hw.inc"

        .export KeyScan, GetNextChar, KeyReset
        .export keyQueue, qHead, qTail  ; (for the tests: keys into the queue)

QUEUE_SIZE      = 16
REPEAT_DELAY    = 25            ; frames before a held key repeats
REPEAT_RATE     = 3             ; frames between repeats
POT_SELECT      = $7F           ; CIA1 port A value that selects port 1 pots

; Matrix positions (column * 8 + row) of the modifier keys
K_LSHIFT        = 15
K_RSHIFT        = 52
K_CTRL          = 58
K_CBM           = 61
MOD_SHIFT       = $01
MOD_CBM         = $02

        .segment "DATA"

keyQueue:       .res QUEUE_SIZE
qHead:          .byte 0         ; next free slot (written by the IRQ)
qTail:          .byte 0         ; next key to read (MainLoop)
lastKey:        .byte $FF
repeatCount:    .byte 0
pressed:        .byte $FF       ; matrix index of the key found this scan
tmpRow:         .byte 0
modifiers:      .byte 0
column:         .byte 0

        .segment "RODATA"

colSelect:
        .byte $FE, $FD, $FB, $F7, $EF, $DF, $BF, $7F

keyNormal:
        .byte KEY_DELETE, CR, KEY_RIGHT, KEY_F7, KEY_F1, KEY_F3, KEY_F5, KEY_DOWN
        .byte "3wa4zse", 0
        .byte "5rd6cftx"
        .byte "7yg8bhuv"
        .byte "9ij0mkon"
        .byte "+pl-.:@,"
        .byte $5C, "*;", KEY_HOME, 0, "=", KEY_UPARROW, "/"
        .byte "1", KEY_LARROW, 0, "2 ", 0, "q", KEY_STOP
keyShifted:
        .byte KEY_INSERT, CR, KEY_LEFT, KEY_F8, KEY_F2, KEY_F4, KEY_F6, KEY_UP
        .byte "#WA$ZSE", 0
        .byte "%RD&CFTX"
        .byte "'YG(BHUV"
        .byte ")IJ0MKON"
        .byte "+PL->[@<"
        .byte $5C, "*]", KEY_CLEAR, 0, "=", KEY_UPARROW, "?"
        .byte "!", KEY_LARROW, 0, $22, " ", 0, "Q", KEY_RUN

        .segment "CODE"

; Interrupt level. Skips the frame when a port 1 device (mouse button,
; joystick) pulls lines low, as those share the keyboard rows.
KeyScan:
        lda #$FF
        sta cia1PortA
        lda cia1PortB
        cmp #$FF
        bne @restore
        lda #0
        sta modifiers
        sta column
@col:   ldx column
        lda colSelect,x
        sta cia1PortA
        lda cia1PortB
        eor #$FF
        beq @nextCol
        ldy #0                  ; row
@row:   lsr
        bcc @nextRow
        pha
        txa                     ; index = column * 8 + row
        asl
        asl
        asl
        sty tmpRow
        ora tmpRow
        jsr Classify
        pla
@nextRow:
        iny
        cpy #8
        bne @row
@nextCol:
        inc column
        lda column
        cmp #8
        bne @col
        jsr Emit
@restore:
        lda #POT_SELECT
        sta cia1PortA
        rts

; A = matrix index of a pressed key: note a modifier or keep the first
; other key in pressed.
Classify:
        cmp #K_LSHIFT
        beq @shift
        cmp #K_RSHIFT
        beq @shift
        cmp #K_CBM
        beq @cbm
        cmp #K_CTRL
        beq @end
        ldx pressed
        cpx #$FF
        bne @end
        sta pressed
@end:   ldx column
        rts
@shift: lda modifiers
        ora #MOD_SHIFT
        sta modifiers
        jmp @end
@cbm:   lda modifiers
        ora #MOD_CBM
        sta modifiers
        jmp @end

; Compare the pressed key with the last one; queue new keys and repeats.
Emit:   lda pressed
        cmp lastKey
        bne @new
        cmp #$FF
        beq @none
        dec repeatCount
        bne @none
        lda #REPEAT_RATE
        sta repeatCount
        jmp @queue
@new:   sta lastKey
        cmp #$FF
        beq @none
        lda #REPEAT_DELAY
        sta repeatCount
@queue: ldx lastKey
        lda modifiers
        and #MOD_SHIFT
        beq @plain
        lda keyShifted,x
        jmp @code
@plain: lda keyNormal,x
@code:  beq @none
        tay
        lda modifiers
        and #MOD_CBM
        beq @put
        tya
        ora #SHORTCUT
        tay
@put:   ldx qHead
        tya
        sta keyQueue,x
        inx
        txa
        and #QUEUE_SIZE - 1
        cmp qTail
        beq @none               ; queue full: drop the key
        sta qHead
        lda pressFlag
        ora #KEYPRESS_BIT
        sta pressFlag
@none:  lda #$FF
        sta pressed
        rts

; GetNextChar: returns A = next key from the queue, 0 if none (Z set
; accordingly); clears KEYPRESS_BIT when the queue is empty. Destroys X.
GetNextChar:
        php
        sei
        ldx qTail
        cpx qHead
        beq @empty
        lda keyQueue,x
        pha
        inx
        txa
        and #QUEUE_SIZE - 1
        sta qTail
        cmp qHead
        bne @more
        lda pressFlag
        and #<~KEYPRESS_BIT
        sta pressFlag
@more:  pla
        plp
        cmp #0
        rts
@empty: lda pressFlag
        and #<~KEYPRESS_BIT
        sta pressFlag
        plp
        lda #0
        rts

        .segment "CODE"

; KeyReset: empty queue, no key held (warm start).
KeyReset:
        lda #0
        sta qHead
        sta qTail
        sta repeatCount
        lda #$FF
        sta lastKey
        sta pressed
        rts
