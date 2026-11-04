; File engine (docs/FILE_ENGINE.md): files by path over the GEOS drives
; and, later, the Ultimate's file system. One resident entry, FileEngine
; (extension jump table +30, folders.s); everything else is in overlay
; modules 22-28:
;   22 engine.s      dispatcher, the caller's state, FE_VERSION, FE_PWD,
;                    FE_CLOSE
;   23 enginepath.s  path: absolute, "." and ".." (Resolve)
;   24 enginepath.s  path: the walk to the folder holding the last part
;   25 enginedir.s   FE_STAT, FE_DF
;   26 enginedir.s   FE_OPENDIR
;   27 enginefile.s  FE_DELETE, FE_RENAME, FE_MKDIR, FE_RMDIR, FE_CD
;   28 enginedir.s   FE_READDIR
; Shared: engine.inc (constants, work area, REU layout), fereu.inc,
; feinfo.inc, feresolve.inc. Own code.
;
; Calling: A = function, arguments in r0-r4, Y = a handle; returns X = 0
; or an error, A = a handle (FE_OPENDIR), results in r0-r4 (r0-r4 kept
; otherwise). The caller's curDrive and every drive's current folder are
; kept; when the engine used a drive, the caller's drive is opened again
; at the end (OpenDisk: curDirHead and the BAM read anew, so call it with
; your BAM changes written). Destroys r5-r15, diskBlkBuf, fileHeader,
; dirEntryBuf.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp, folderT, folderS

        .segment "OVL22"
        .scope Mod22

        jmp OvFileEngine        ; entry 0
        jmp OvVersion           ; entry 3
        jmp OvPwd               ; entry 6
        jmp OvClose             ; entry 9
        jmp OvNotYet            ; entry 12

        .include "fereu.inc"

; (module, entry) per function number
Funcs:  .byte 22, 3             ; FE_VERSION
        .byte 25, 0             ; FE_STAT
        .byte 26, 0             ; FE_OPENDIR
        .byte 28, 0             ; FE_READDIR
        .byte 22, 9             ; FE_CLOSE
        .byte 22, 12            ; FE_COPY (E2)
        .byte 22, 12            ; FE_MOVE (E2)
        .byte 27, 0             ; FE_DELETE
        .byte 27, 6             ; FE_MKDIR
        .byte 27, 9             ; FE_RMDIR
        .byte 27, 3             ; FE_RENAME
        .byte 27, 12            ; FE_CD
        .byte 22, 6             ; FE_PWD
        .byte 22, 12            ; FE_OPEN (E2)
        .byte 22, 12            ; FE_READ (E2)
        .byte 22, 12            ; FE_WRITE (E2)
        .byte 25, 3             ; FE_DF
        .byte 22, 12            ; FE_MOUNT (E4)
        .byte 22, 12            ; FE_UMOUNT (E4)
        .assert * - Funcs = 2 * FE_COUNT, error, "engine.s: Funcs and FE_COUNT differ"

; OvFileEngine: save the caller's state, call the function (Call),
; restore, results to r0-r4.
OvFileEngine:
        sta feFunc
        sty feY
        ldx #9
@args:  lda r0L,x
        sta argR,x
        dex
        bpl @args
        lda curDrive
        sta saveDrive
        ldx #3
@fold:  lda folderT,x
        sta saveFT,x
        lda folderS,x
        sta saveFS,x
        dex
        bpl @fold
        lda #0
        sta feTouched
        jsr Setup
        lda feFunc
        cmp #FE_COUNT
        bcs @bad
        asl
        tay
        lda Funcs,y
        sta Call+3
        lda Funcs+1,y
        sta Call+4
        ldy feY
        jsr Call
@done:  sta feA
        stx feErr
        lda feTouched
        beq @out
        ldx #3
@back:  lda saveFT,x
        sta folderT,x
        lda saveFS,x
        sta folderS,x
        dex
        bpl @back
        lda saveDrive
        jsr SetDevice
        jsr OpenDisk            ; (an error is dropped: the caller's drive
@out:   ldx #9                  ; is as the caller left it)
@res:   lda argR,x
        sta r0L,x
        dex
        bpl @res
        lda feA
        ldx feErr
        rts
@bad:   ldx #FE_NOT_SUPPORTED
        bne @done

; Call: the stub through which the function is called; its two bytes are
; written just before (OvlCall reads them before it fetches the other
; module, and this module comes back from the REU unchanged on the way
; out). Called with jsr: OvlCall returns to the stub's caller.
Call:   jsr OvlCall
        .byte 0, 0

; Setup: the REU state (engine.inc) made when it is not there yet (after
; power-on): the current directory "/", every handle free. diskBlkBuf
; and the start of fileHeader are the source.
Setup:  jsr Magic
        ldy #REU_FETCH
        jsr ReuOp
        lda diskBlkBuf
        cmp #'F'
        bne @make
        lda diskBlkBuf+1
        cmp #'E'
        bne @make
        lda diskBlkBuf+2
        cmp #FE_LAYOUT
        beq @end
@make:  lda #0
        tay
@zero:  sta diskBlkBuf,y
        sta fileHeader,y
        iny
        bne @zero
        lda #'/'
        sta diskBlkBuf
        lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        lda #<FE_CWD
        sta r1L
        lda #>FE_CWD
        sta r1H
        lda #<(FE_HANDLES + FE_HANDLES_N * FE_HSIZE - FE_CWD)
        sta r2L
        lda #>(FE_HANDLES + FE_HANDLES_N * FE_HSIZE - FE_CWD)
        sta r2H
        ldy #REU_STASH
        jsr ReuOp
        lda #'F'
        sta diskBlkBuf
        lda #'E'
        sta diskBlkBuf+1
        lda #FE_LAYOUT
        sta diskBlkBuf+2
        jsr Magic
        ldy #REU_STASH
        jmp ReuOp
@end:   rts
        .assert FE_HANDLES + FE_HANDLES_N * FE_HSIZE - FE_CWD <= $200, error, "Setup: more than diskBlkBuf and fileHeader"

; Magic: r0-r2 for the three bytes at FE_MAGIC <-> diskBlkBuf.
Magic:  lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        lda #<FE_MAGIC
        sta r1L
        lda #>FE_MAGIC
        sta r1H
        lda #3
        sta r2L
        lda #0
        sta r2H
        rts

; FE_VERSION: r0 = FE_VER.
OvVersion:
        lda #<FE_VER
        sta argR0
        lda #>FE_VER
        sta argR0+1
        ldx #0
        rts

; FE_PWD: r0 = a buffer of 128 bytes: the current directory, zero-ended.
OvPwd:  lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        lda #<FE_CWD
        sta r1L
        lda #>FE_CWD
        sta r1H
        lda #FE_PATH_MAX + 1
        sta r2L
        lda #0
        sta r2H
        ldy #REU_FETCH
        jsr ReuOp
        ldx #0
        rts

; FE_CLOSE: Y = a handle, or $FF for all of them (a program starting
; afresh).
OvClose:
        cpy #$FF
        beq @all
        cpy #FE_HANDLES_N
        bcs @bad
        sty feHandle
        jsr Free
        ldx #0
        rts
@all:   ldy #FE_HANDLES_N - 1
@one:   sty feHandle
        jsr Free
        ldy feHandle
        dey
        bpl @one
        ldx #0
        rts
@bad:   ldx #FE_BAD_HANDLE
        rts

; Free: handle feHandle free (only its type byte written).
Free:   lda #HT_FREE
        sta feH + H_TYPE
        jsr HandleRegs          ; (then the length cut to one)
        ldy #REU_STASH
        lda #1
        sta r2L
        jmp ReuOp

; Functions of a later step.
OvNotYet:
        ldx #FE_NOT_SUPPORTED
        rts

        .endscope
