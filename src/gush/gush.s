; gush, the GeoUltra shell (docs/GUSH.md): a GEOS application with a text
; console (con.s), a line editor and commands over the file engine. Step
; 1.3: the frame (screen, status line), the line editor with history
; (edit.s), words and wildcards (parse.s), the commands (cmds.s). Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import ConInit, ConPut, ConPuts, ConNewLine, ConClear, ConCursor
        .import ConStatus, conCol, conRow
        .import EdKey, EdPress, Prompt, VarsInit, RunRc, HistLoad
        .import OvlInit, ovlOk
        .export FileEngine, Status, pwdBuf, startDrive

EnterDeskTop    = $C22C         ; GEOS jump table
StartMouseMode  = $C14E

        .segment "CODE"

Start:  jsr OvlInit              ; (first: dirEntryBuf is gush's entry)
        lda curDrive            ; (cd without a path: its root)
        sta startDrive
        lda guExtTable          ; FileEngine: the extension table + 30
        clc
        adc #FE_ENTRY
        sta feVec
        lda guExtTable+1
        adc #0
        sta feVec+1
        lda #ST_WR_FORE         ; the foreground only (gush redraws from
        sta dispBufferOn        ; its shadow)
        jsr VarsInit            ; HOME, PATH
        jsr ConInit
        jsr Status
        lda #<Hello
        sta r0L
        lda #>Hello
        sta r0H
        jsr ConPuts
        lda ovlOk               ; (overlay commands fail without them)
        bne :+
        lda #<NoOvl
        sta r0L
        lda #>NoOvl
        sta r0H
        jsr ConPuts
:       jsr HistLoad            ; HOME/gush_history, when there
        jsr RunRc               ; HOME/gushrc, when there
        jsr Prompt
        lda #<EdKey
        sta keyVector
        lda #>EdKey
        sta keyVector+1
        clc                     ; the mouse on, where it is (clicks: the
        jsr StartMouseMode      ; cursor on the line, EdPress)
        lda #<EdPress
        sta otherPressVec
        lda #>EdPress
        sta otherPressVec+1
        lda #<Tick
        sta appMain
        lda #>Tick
        sta appMain+1
        rts                     ; (to MainLoop)

; FileEngine: the engine's entry (A = function, Y = handle, r0-r4).
FileEngine:
        jmp (feVec)

; Tick (appMain, every MainLoop pass): the status line again when the
; minute changed.
Tick:   lda minutes
        cmp shownMinute
        beq @end
        jsr Status
@end:   rts

; Status: the status line with the current directory and the time.
Status: lda minutes
        sta shownMinute
        lda #<pwdBuf
        sta r0L
        lda #>pwdBuf
        sta r0H
        lda #FE_PWD
        jsr FileEngine
        txa
        beq :+
        lda #0                  ; (no engine: no path)
        sta pwdBuf
:       lda #<pwdBuf
        sta r0L
        lda #>pwdBuf
        sta r0H
        jmp ConStatus

Hello:  .byte "gush, the GeoUltra shell (step 3)", CR, 0
NoOvl:  .byte "gush: its overlays could not be read: file", CR
        .byte "and system commands, test and read fail.", CR, 0

        .segment "DATA"

feVec:          .word 0
shownMinute:    .byte $FF
startDrive:     .byte 8

        .segment "BSS"

pwdBuf:         .res 256
