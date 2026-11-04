; File engine: paths, for the function modules (and the walk, module 24).
; Assembled into each module that needs it: an overlay module cannot call
; another's code. The stubs return here (they are called with jsr).

; Resolve: r0 = a path. fePath its absolute form; then walked (module
; 24): feKind, feDrive, feName, and on a GEOS drive that drive current
; (feTouched) in the folder holding feName. X = 0 or an error.
Resolve:
        jsr OvlCall
        .byte 23, 0

; FindName: FindFile on feName (dirEntryBuf, r1, r5). X = 0 or an error.
FindName:
        lda #<feName
        sta r6L
        lda #>feName
        sta r6H
        jmp FindFile

; EnterName: into the folder feName (module 12's SetCurDir); EnterR0:
; into the folder named at r0. X = 0, FILE_NOT_FOUND, FE_NOT_FOLDER (a
; file, a partition that is no sub-directory, a drive without folders)
; or a disk error.
EnterName:
        lda #<feName
        sta r0L
        lda #>feName
        sta r0H
EnterR0:
        jsr SetCurDir
        cpx #STRUCT_MISMAT
        bne @end
        ldx #FE_NOT_FOLDER
@end:   rts

SetCurDir:
        jsr OvlCall             ; (extension table +5, folders.s)
        .byte 12, 3

; IsDir: C clear when dirEntryBuf is a folder (native DIR, or a 1581
; partition: CBM type 6 or 5).
IsDir:  lda dirEntryBuf
        and #$07
        cmp #5
        beq @yes
        cmp #6
        beq @yes
        sec
        rts
@yes:   clc
        rts
