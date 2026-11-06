; gush: the line editor and history (docs/GUSH.md, "Keys and the line
; editor"). The input line (up to LINE_MAX characters) after the prompt on
; one screen row, scrolled sideways when longer than the row; keys from
; keyVector; the last HIST_N lines in the application's REU (bank
; HIST_BANK through StashRAM/FetchRAM; bank 0 is MoveData's scratch).
; GEOS gives CTRL no code: Ctrl looks at the keyboard matrix itself. Own
; code.

        .include "geos.inc"
        .include "hw.inc"
        .include "gush.inc"

        .import ConPut, ConNewLine, ConClear, ConSet, ConCursor, conCol, conRow
        .import ExecLine
        .export EdKey, EdPress, Prompt, lineBuf, lineLen, testCtrl
        .export histTop, histCount, histSlot, histBuf, Fetch, Keep
        .export linePos, prevKey, Show, InsCh
        .import Complete

StashRAM        = $C2C8         ; GEOS jump table
FetchRAM        = $C2CB

PROMPT_W        = 2             ; "$ "
VIEW_W          = COLS - PROMPT_W
HIST_N          = 128           ; lines kept, 256 bytes each (32 KB; a
                                ; power of 2; hist.s saves 100 of them)
HIST_BANK       = 1

        .segment "CODE"

; Prompt: "$ " on the current row (the cursor at its start), an empty
; line.
Prompt: lda #0
        sta lineLen
        sta linePos
        sta viewAt
        sta histAt
        lda #'$'
        jsr ConPut
        lda #' '
        jsr ConPut
        jmp Show

; Show: the visible part of the line drawn, the cursor on it.
Show:   lda linePos             ; the view follows the cursor
        cmp viewAt
        bcs :+
        sta viewAt
:       sec
        sbc viewAt
        cmp #VIEW_W
        bcc @draw
        lda linePos
        sec
        sbc #VIEW_W - 1
        sta viewAt
@draw:  lda #0
        sta drawAt
@cell:  lda drawAt
        clc
        adc viewAt
        tax
        lda #' '
        cpx lineLen
        bcs :+
        lda lineBuf,x
:       pha
        lda drawAt
        clc
        adc #PROMPT_W
        tax
        pla
        ldy conRow
        jsr ConSet
        inc drawAt
        lda drawAt
        cmp #VIEW_W
        bne @cell
        lda linePos
        sec
        sbc viewAt
        clc
        adc #PROMPT_W
        sta conCol
        lda #1
        jmp ConCursor

; EdPress (otherPressVec): a mouse press on the input line puts the
; cursor on the character pressed (or at the line's end). Only while the
; editor has the keys (keyVector = EdKey: not while a question waits).
EdPress:
        lda mouseData           ; (a press, not the release)
        bmi @end
        lda keyVector
        cmp #<EdKey
        bne @end
        lda keyVector+1
        cmp #>EdKey
        bne @end
        lda mouseYPos           ; its row: 8 pixels each
        lsr a
        lsr a
        lsr a
        cmp conRow
        bne @end
        lda mouseXPos           ; its column: 6 pixels each
        ldx mouseXPos+1
        ldy #0
@col:   cpx #0
        bne :+
        cmp #6
        bcc @got
:       sec
        sbc #6
        bcs :+
        dex
:       iny
        bne @col
@got:   tya                     ; the line's character there
        sec
        sbc #PROMPT_W
        bcs :+
        lda #0                  ; (on the prompt: the view's first)
:       clc
        adc viewAt
        cmp lineLen
        bcc :+
        lda lineLen
:       pha
        lda #0                  ; (the cursor off while it moves)
        jsr ConCursor
        pla
        sta linePos
        jmp Show
@end:   rts

; EdKey (keyVector): one key in keyData.
EdKey:  lda #0                  ; the cursor off while the line changes
        jsr ConCursor
        lda lastKey             ; (the key before: completion, a second <-)
        sta prevKey
        lda keyData
        sta lastKey
        jsr Ctrl                ; CTRL held: A, E, K, U, C
        bcc @plain
        and #$1F | $40          ; (either case)
        ora #$20
        ldx #CtrlKeys_n - 1
@ck:    cmp CtrlKeys,x
        beq @ctrl
        dex
        bpl @ck
        jmp Show
@ctrl:  txa
        asl a
        tax
        lda CtrlDo+1,x
        pha
        lda CtrlDo,x
        pha
        rts
@plain: cmp #KEY_UPARROW         ; up arrow: "|" (the C64 has no such
        bne :+                  ; key; user, 2026-11-06)
        lda #'|'
        jmp Insert
:       cmp #SHORTCUT           ; C= + a key: ASCII the C64 has no key
        bcc @edit               ; for (CbmKeys)
        and #$7F
        ldx #CbmKeys_n - 1
@cb:    cmp CbmKeys,x
        beq @cbm
        dex
        bpl @cb
        jmp Show
@cbm:   lda CbmChars,x
        jmp Insert
@edit:  ldx #Keys_n - 1         ; an editing key?
@key:   cmp Keys,x
        beq @do
        dex
        bpl @key
        cmp #' '                ; else a character, if printable
        bcc ToShow
        cmp #127
        bcs ToShow
        jmp Insert
@do:    txa
        asl a
        tax
        lda KeyDo+1,x
        pha
        lda KeyDo,x
        pha
        rts

Keys:   .byte CR, KEY_DELETE, KEY_INSERT, KEY_LEFT, KEY_RIGHT, KEY_HOME
        .byte KEY_CLEAR, KEY_UP, KEY_DOWN, KEY_STOP, KEY_LARROW
Keys_n = * - Keys
KeyDo:  .word Enter-1, Back-1, Forward-1, Left-1, Right-1, Home-1
        .word Clear-1, Older-1, Newer-1, Drop-1, Complete-1
CbmKeys:                        ; C= with these (SHIFT as on the key) ...
        .byte "()-'", KEY_UPARROW
CbmKeys_n = * - CbmKeys
CbmChars:                       ; ... gives these
        .byte "{}_`~"
CtrlKeys:
        .byte "aekuc"
CtrlKeys_n = * - CtrlKeys
CtrlDo: .word Home-1, End-1, CutEnd-1, CutStart-1, Drop-1

ToShow: jmp Show                ; (in reach of the routines' branches)

; Insert: character A at the cursor.
Insert: jsr InsCh
        jmp Show

; InsCh: character A at the cursor, the line not drawn. C set when the
; line is full (nothing changed). (complete.s too.)
InsCh:  ldx lineLen
        cpx #LINE_MAX
        bcs @full
        pha
@move:  cpx linePos             ; the rest one place right
        beq @put
        lda lineBuf-1,x
        sta lineBuf,x
        dex
        bne @move
@put:   pla
        sta lineBuf,x
        inc lineLen
        inc linePos
        clc
@full:  rts

; Back (DEL): the character before the cursor off.
Back:   ldx linePos
        beq ToShow
        dec linePos
; Forward (INST): the character at the cursor off.
Forward:
        ldx linePos
        cpx lineLen
        bcs ToShow
@move:  lda lineBuf+1,x
        sta lineBuf,x
        inx
        cpx lineLen
        bcc @move
        dec lineLen
        jmp Show

Left:   lda linePos
        beq ToShow
        dec linePos
        jmp Show
Right:  lda linePos
        cmp lineLen
        bcs ToShow
        inc linePos
        jmp Show
Home:   lda #0
        sta linePos
        jmp Show
End:    lda lineLen
        sta linePos
        jmp Show

; CutEnd (CTRL+K): the line after the cursor off.
CutEnd: lda linePos
        sta lineLen
        jmp Show

; CutStart (CTRL+U): the line before the cursor off.
CutStart:
        ldx #0
        ldy linePos
@move:  cpy lineLen
        beq @end
        lda lineBuf,y
        sta lineBuf,x
        inx
        iny
        bne @move
@end:   stx lineLen
        lda #0
        sta linePos
        jmp Show

; Clear (CLR): the screen cleared, the line kept on row 1.
Clear:  jsr ConClear
        lda #'$'
        jsr ConPut
        lda #' '
        jsr ConPut
        jmp Show

; Drop (CTRL+C, RUN/STOP): the line left as it is, "^C", a new prompt.
Drop:   jsr End
        lda #0
        jsr ConCursor
        lda #'^'
        jsr Tail
        lda #'C'
        jsr ConPut
        jsr ConNewLine
        jmp Prompt

; Enter (RETURN): the line into the history and run.
Enter:  jsr End                 ; the whole line shown
        lda #0
        jsr ConCursor
        lda #0
        jsr Tail                ; (the cursor after it)
        jsr ConNewLine
        ldx lineLen
        lda #0
        sta lineBuf,x
        jsr Keep
        jsr ExecLine            ; (its statements: flow.s)
        jmp Prompt

; Tail: the cursor column after the visible line's end; A (not 0)
; written there.
Tail:   pha
        lda lineLen
        sec
        sbc viewAt
        cmp #VIEW_W
        bcc :+
        lda #VIEW_W - 1
:       clc
        adc #PROMPT_W
        sta conCol
        pla
        beq @end
        jmp ConPut
@end:   rts

; --- History ---------------------------------------------------------------

; Keep: the line (if not empty and not the newest already) as the newest.
Keep:   lda lineLen
        beq @end
        jsr Newest              ; the same as the newest: not again
        lda histCount
        beq @new
        jsr Fetch
        ldx #$FF
@cmp:   inx
        lda histBuf,x
        cmp lineBuf,x
        bne @new
        cmp #0
        bne @cmp
        rts
@new:   lda histTop             ; the next slot
        clc
        adc #1
        and #HIST_N - 1
        sta histTop
        lda histCount
        cmp #HIST_N
        bcs :+
        inc histCount
:       jsr Newest
        lda #<lineBuf
        sta r0L
        lda #>lineBuf
        sta r0H
        ldy #StashRAM - StashRAM ; (0: stash)
        jmp RamOp
@end:   rts

; Older (cursor up), Newer (cursor down): the history browsed; past the
; newest an empty line.
Older:  lda histAt
        cmp histCount
        bcs @end
        inc histAt
        jmp Recall
@end:   jmp Show
Newer:  lda histAt
        beq @end
        dec histAt
        bne Recall
        lda #0
        sta lineLen
        sta linePos
@end:   jmp Show

; Recall: history line histAt (1: the newest) into the input line, the
; cursor and the view at its start (user, 2026-11-06: a long line showed
; its end; CTRL+E goes there).
Recall: lda histTop
        sec
        sbc histAt
        clc
        adc #1
        and #HIST_N - 1
        sta histSlot
        jsr Fetch
        ldx #$FF
@copy:  inx
        lda histBuf,x
        sta lineBuf,x
        bne @copy
        stx lineLen
        lda #0
        sta linePos
        sta viewAt
        jmp Show

; Newest: histSlot = histTop.
Newest: lda histTop
        sta histSlot
        rts

; Fetch: history slot histSlot to histBuf.
Fetch:  lda #<histBuf
        sta r0L
        lda #>histBuf
        sta r0H
        ldy #1
; RamOp: Y = 0 stash, 1 fetch: 256 bytes at r0 <-> slot histSlot.
RamOp:  lda #0
        sta r1L
        lda histSlot
        sta r1H
        lda #0
        sta r2L
        lda #1
        sta r2H
        lda #HIST_BANK
        sta r3L
        tya
        beq @stash
        jmp FetchRAM
@stash: jmp StashRAM
        .assert HIST_N <= 256 && (HIST_N & (HIST_N - 1)) = 0, error, "history: a power of two"

; --- CTRL --------------------------------------------------------------------

; Ctrl: C set when CTRL is held (the keyboard matrix: row 7, bit 2), or
; when a test set testCtrl. A kept.
Ctrl:   pha
        lda testCtrl
        bne @yes
        php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda $DC00
        pha
        lda #$7F                ; row 7
        sta $DC00
        lda $DC01
        and #$04                ; CTRL: 0 when held
        sta ctrlBit
        pla
        sta $DC00
        pla
        sta CPU_PORT
        plp
        lda ctrlBit
        bne @no
@yes:   pla
        sec
        rts
@no:    pla
        clc
        rts

        .segment "DATA"

lineLen:        .byte 0
linePos:        .byte 0
lastKey:        .byte 0
prevKey:        .byte 0
viewAt:         .byte 0
drawAt:         .byte 0
histTop:        .byte HIST_N - 1        ; (the first line goes to slot 0)
histCount:      .byte 0
histAt:         .byte 0
histSlot:       .byte 0
ctrlBit:        .byte 0
testCtrl:       .byte 0                 ; (tests: nonzero = CTRL held)

        .segment "BSS"

lineBuf:        .res 256
histBuf:        .res 256
