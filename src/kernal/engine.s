; File engine (docs/FILE_ENGINE.md): files by path over the GEOS drives
; and, later, the Ultimate's file system. One resident entry, FileEngine
; (extension jump table +30, folders.s); everything else is in overlay
; modules 22-79:
;   22 engine.s      dispatcher, the caller's state, FE_VERSION, FE_PWD,
;                    FE_CLOSE
;   23 enginepath.s  path: absolute, "." and ".." (Resolve)
;   24 enginepath.s  path: the walk to the folder holding the last part
;   25 enginedir.s   FE_STAT, FE_DF
;   26 enginedir.s   FE_OPENDIR
;   27 enginefile.s  FE_DELETE, FE_RENAME, FE_MKDIR, FE_RMDIR, FE_CD,
;                    FE_SELECT
;   28 enginedir.s   FE_READDIR
;   29 enginecopy.s  FE_COPY, FE_MOVE (the source, a move as a rename)
;   30 enginecopy.s  the target of a copy, checked
;   31 enginecopy.s  the blocks of a copy, its directory entry
;   32 enginestream.s FE_OPEN
;   33 enginestream.s a new file for FE_OPEN
;   34 enginestream.s FE_READ
;   35 enginestream.s FE_WRITE
;   36 engineult.s   the Ultimate: the exchange, its folders (feult.inc,
;                    fecd.inc)
;   37 engineult.s   FE_STAT on the Ultimate
;   38 engineult.s   FE_OPENDIR on the Ultimate: the listing read whole
;   39 engineult.s   FE_READDIR on an Ultimate listing
;   40 engineult.s   FE_READDIR on "/": the drives, the Ultimate's tops
;   41 engineult.s   FE_DELETE, FE_MKDIR, FE_RMDIR, FE_RENAME, FE_CD on
;                    the Ultimate
;   42 enginexfer.s  FE_COPY, FE_MOVE onto the Ultimate (raw)
;   43 enginexfer.s  FE_COPY, FE_MOVE from the Ultimate: the source, target
;   44 enginexfer.s  its blocks onto the GEOS drive
;   45 enginexfer.s  a GEOS file's blocks onto the Ultimate
;   46 enginexfer.s  a new entry's fields from an Ultimate file
;   47 engineult.s   an Ultimate listing read whole (READ_DIR)
;   48 enginelong.s  long names looked up
;   49 enginelong.s  GU.LONGNAMES kept (a record set, dropped)
;   50 enginelong.s  short names made
;   51 enginelong.s  names: a listing's entries, dropped, FE_GETLONG
;   54 enginelong.s  rename and mkdir with long names
;   55 sysdrive.s    FE_RUNSYS: an application on drive E started
;   52 enginelong.s  a copy's new entry (and its long name)
;   53 enginelong.s  GU.LONGNAMES made
;   56 enginecvt.s   a GEOS file onto the Ultimate as CVT (header, data)
;   57 enginecvt.s   a CVT from the Ultimate converted (header, data)
;   58 enginecvt.s   a VLIR file's table and records as CVT
;   59 enginecvt.s   a CVT's VLIR table and records converted
;   60 enginecvt.s   a CVT recognised (its signature block)
;   61 enginestreamu.s FE_OPEN on the Ultimate
;   62 enginestreamu.s FE_READ on the Ultimate
;   63 enginestreamu.s FE_WRITE on the Ultimate
;   64 enginestreamu.s an Ultimate stream's setup: handle, open, close
;   65 enginemount.s FE_MOUNT: the image checked
;   66 enginemount.s FE_UMOUNT: a drive emptied (after the write-back)
;   67 enginemount.s MOUNTS.INI written anew (opened, closed)
;   68 enginemount.s FE_MOUNT: free banks found, the image loaded
;   69 enginemount.s FE_MOUNT: the new drive entered
;   70 enginemount.s MOUNTS.INI's text
;   71 enginemkimg.s FE_MKIMG: banks found, cleared, the image saved
;   72 enginemkimg.s an empty D64's or D71's blocks
;   73 enginemkimg.s an empty native image's blocks; the banks cleared
;   74 enginemkimg.s an empty D81's blocks
;   75 enginesys.s   FE_TURBO, FE_HOME, FE_SETTIME, FE_REBOOT
;   76 enginentp.s   FE_NTP: the exchange with the server
;   77 enginentp.s   SETTINGS.INI's [time] read
;   78 enginentp.s   the time as a date, the clocks set
;   79 enginentp.s   SETTINGS.INI's [time] lines
;   80 enginenet.s   FE_UCI: a command to the Ultimate, its reply
;   83 engineuu.s    FE_MOVE on one Ultimate volume: a rename from its top
;   84 engineuu.s    FE_COPY from the Ultimate onto it: its own COPY
;   85 engineuu.s    such a copy under another name: through GU.TMP
; Shared: engine.inc (constants, work area, REU layout), feblock.inc,
; fecd.inc, fecvtout.inc, fecvtread.inc, fecvtwrite.inc, fedrive.inc,
; fefat.inc, fefmt.inc, fehome.inc, felong.inc, femount.inc, fepath.inc,
; feprog.inc, fereu.inc, festream.inc, festreamu.inc, fetype.inc,
; fework.inc, fegive.inc, fehandle.inc, feinfo.inc, fematch.inc,
; fename.inc, feresolve.inc, feult.inc; uci.inc (the UCI handshake).
; Own code.
;
; Calling: A = function, arguments in r0-r4, Y = a handle; returns X = 0
; or an error, A = a handle (FE_OPENDIR), results in r0-r4 (r0-r4 kept
; otherwise). The caller's curDrive and every drive's current folder are
; kept; when the engine used a drive, the caller's drive is opened again
; at the end (OpenDisk: curDirHead and the BAM read anew, so call it with
; your BAM changes written). Destroys r5-r15, diskBlkBuf, fileHeader,
; fileTrScTab, dirEntryBuf.

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

        .include "fereu.inc"

; (module, entry) per function number
Funcs:  .byte 22, 3             ; FE_VERSION
        .byte 25, 0             ; FE_STAT
        .byte 26, 0             ; FE_OPENDIR
        .byte 28, 0             ; FE_READDIR
        .byte 22, 9             ; FE_CLOSE
        .byte 29, 0             ; FE_COPY
        .byte 29, 3             ; FE_MOVE
        .byte 27, 0             ; FE_DELETE
        .byte 27, 6             ; FE_MKDIR
        .byte 27, 9             ; FE_RMDIR
        .byte 27, 3             ; FE_RENAME
        .byte 27, 12            ; FE_CD
        .byte 22, 6             ; FE_PWD
        .byte 32, 0             ; FE_OPEN
        .byte 34, 0             ; FE_READ
        .byte 35, 0             ; FE_WRITE
        .byte 25, 3             ; FE_DF
        .byte 65, 0             ; FE_MOUNT (enginemount.s)
        .byte 66, 0             ; FE_UMOUNT
        .byte 51, 6             ; FE_GETLONG
        .byte 27, 3             ; FE_SETLONG (= FE_RENAME)
        .byte 27, 15            ; FE_SELECT
        .byte 55, 0             ; FE_RUNSYS (sysdrive.s)
        .byte 66, 6             ; FE_MOUNTINFO (enginemount.s)
        .byte 71, 0             ; FE_MKIMG (enginemkimg.s)
        .byte 75, 0             ; FE_TURBO (enginesys.s)
        .byte 75, 3             ; FE_HOME
        .byte 75, 6             ; FE_SETTIME
        .byte 75, 9             ; FE_REBOOT
        .byte 76, 0             ; FE_NTP (enginentp.s)
        .byte 80, 0             ; FE_UCI (enginenet.s)
        .byte 86, 3             ; FE_POINTER (pointer.s)
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
        sta feUlt               ; (a function taking Ultimate paths sets it)
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
        jsr HideE               ; (drive E shown for /e: its slot back)
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
HideE:  jsr OvlCall             ; (module 81, sysenter.s)
        .byte 81, 12

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

; FE_PWD: r0 = a buffer of 256 bytes: the current directory, zero-ended.
OvPwd:  lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        lda #<FE_CWD
        sta r1L
        lda #>FE_CWD
        sta r1H
        lda #<(FE_PATH_MAX + 1)
        sta r2L
        lda #>(FE_PATH_MAX + 1)
        sta r2H
        ldy #REU_FETCH
        jsr ReuOp
        ldx #0
        rts

; FE_CLOSE: Y = a handle, or $FF for all of them (a program starting
; afresh). A stream needs nothing more: FE_WRITE leaves its file whole.
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

        .endscope
