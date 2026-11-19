; GeoUltra Desktop: paths through disk images for the recent documents
; and for opening a document inside an image that is not mounted
; (overlay 6, ovl.s; docs/design/DESKTOP.md "Recent documents"; the user's
; decision of 2026-11-18: a recent document on an image unmounted since
; did nothing when clicked; it should offer to mount the image again).
; All on side.s's work buffer (a path, workLen its length):
; - ImgPath (RecentAdd): "/x..." on a drive with a mounted image becomes
;   the image's path on the Ultimate, so the entry outlives the mount;
; - ImgLocal (side.s OpenAt): a folder path through a disk image file
;   becomes "/x" + the rest when that image is mounted on drive x; when
;   it is not, work becomes the image's folder, entryName the image's
;   name, the rest kept (for Mount and AfterMount);
; - NameImg: entryName = the image's name again (the list's Fetches
;   overwrite it);
; - AfterMount: after Mount, when the list is at a drive's root ("/x"),
;   work = "/x" + the rest.
; Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import work, workLen, entryName, path, FileEngine, text
        .export Ov_ImgPath, Ov_ImgLocal, Ov_NameImg, Ov_AfterMount

INFO_MAX        = 64            ; FE_MOUNTINFO's buffer
; The image's name and the rest of the path must outlast other overlays
; (Ask, Mount): an overlay is loaded afresh each time, its own bytes
; with it. They live in side.s's shared text, past what Mount (full, at
; its start), the path line (cutPath) and the icon view (at its end) use
; meanwhile; the recent list's save after the document opened comes
; when they are no longer needed.
IMG_AT          = 1024
imgName         = text + IMG_AT
rest            = imgName + PATH_LEN + 1
        .assert IMG_AT + 2 * (PATH_LEN + 1) < TEXT_MAX - 256, error, "imgpath.s: text's room"

NAME_MAX        = PATH_LEN      ; entryName's room (Ultimate names are long)

        .segment "OV6"

Ov_ImgPath = ImgPath
Ov_ImgLocal = ImgLocal
Ov_NameImg = NameImg
Ov_AfterMount = AfterMount

; ImgPath: work "/x" or "/x/..." (x a drive A-D with a mounted image):
; the image's path in front of the rest instead; else as it was. A path
; that would not fit stays as it was. Destroys A, X, Y, r0-r3.
ImgPath:
        lda work
        cmp #'/'
        bne @end
        lda work + 1
        cmp #'a'
        bcc @end
        cmp #'d' + 1
        bcs @end
        lda work + 2
        beq @drive
        cmp #'/'
        bne @end
@drive: lda work + 1
        jsr Info                ; ibuf = its image's path
        bcs @end
        ldy #0                  ; ibuf + work from 2 on, into work
        ldx #2
@len:   lda ibuf,y
        beq @rest
        iny
        bne @len
@rest:  lda work,x
        sta ibuf,y
        beq @copy
        iny
        inx
        cpy #PATH_LEN
        bcc @rest
        rts                     ; (too long: as it was)
@copy:  sty workLen
@c:     lda ibuf,y
        sta work,y
        dey
        bpl @c
@end:   rts

; Info: A = a drive letter ('a'-'d'): its image's path in ibuf (lower
; case as FE_MOUNTINFO gives it). C set: no image there.
Info:   sta drvPath + 1
        lda #<drvPath
        sta r0L
        lda #>drvPath
        sta r0H
        lda #<ibuf
        sta r1L
        lda #>ibuf
        sta r1H
        lda #FE_MOUNTINFO
        jsr FileEngine
        cpx #1                  ; (X = 0: C clear)
        rts

; ImgLocal: see above. C clear: work is a path to open (unchanged when
; it goes through no image); C set: the image is not mounted (work its
; folder, entryName its name). Destroys A, X, Y, r0-r3.
ImgLocal:
        ldy #0                  ; the first part that is an image's name:
        sty segAt               ; its end in segEnd
@seg:   lda work,y
        beq @none
        cmp #'/'
        bne @next
        jsr IsImgSeg            ; (the part ending at y)
        bcc @found
        iny
        sty segAt
        bne @seg                ; (always)
@next:  iny
        bne @seg
@none:  jsr IsImgSeg            ; (the last part)
        bcc @found
        clc
        rts
@found: sty segEnd
        ldx #0                  ; rest = from segEnd
@r:     lda work,y
        sta rest,x
        beq :+
        iny
        inx
        bne @r
:       lda #0                  ; work = up to segEnd: the image's path
        ldy segEnd
        sta work,y
        lda #'a'                ; mounted on one of the drives?
        sta drv
@drv:   lda drv
        jsr Info
        bcs @other
        jsr SameImg
        bcc @mounted
@other: inc drv
        lda drv
        cmp #'d' + 1
        bcc @drv
        ldy segAt               ; not mounted: entryName = its name,
        ldx #0                  ; work = its folder
@n:     lda work,y
        sta entryName,x
        sta imgName,x
        beq :+
        iny
        inx
        cpx #NAME_MAX - 1
        bcc @n
        lda #0
        sta entryName,x
        sta imgName,x
:       ldy segAt               ; the folder: up to the "/" before it
        cpy #1                  ; ("/" for an image in "/x")
        beq :+
        dey
:       lda #0
        sta work,y
        sec
        rts
@mounted:
        lda #'/'                ; work = "/x" + rest
        sta work
        lda drv
        sta work + 1
        lda #2
        jmp Rest

; AfterMount: C clear and work = path + rest when the list is at a
; drive's root ("/x": Mount mounted the image there); C set when not
; (the dialog was cancelled, or the mount failed).
AfterMount:
        lda path
        cmp #'/'
        bne @no
        lda path + 2
        bne @no
        lda path + 1
        sta work + 1
        lda #'/'
        sta work
        lda #2
        jmp Rest
@no:    sec
        rts

; Rest: rest after work's first A characters (bounded); C clear.
Rest:   tay
        ldx #0
@c:     lda rest,x
        sta work,y
        beq @end
        iny
        inx
        cpy #PATH_LEN
        bcc @c
        lda #0
        sta work + PATH_LEN - 1
@end:   sty workLen
        clc
        rts

; NameImg: entryName = the image's name (ImgLocal's).
NameImg:
        ldx #NAME_MAX - 1
@c:     lda imgName,x
        sta entryName,x
        dex
        bpl @c
        rts

; IsImgSeg: C clear when the part of work from segAt to Y (exclusive)
; ends in .d64, .d71, .d81 or .dnp (any case). Y kept.
IsImgSeg:
        tya
        sec
        sbc segAt
        cmp #5                  ; at least "x.d64"
        bcc @no
        lda work - 4,y
        cmp #'.'
        bne @no
        ldx #0
@try:   lda work - 3,y
        jsr Fold
        cmp Exts,x
        bne @next
        lda work - 2,y
        jsr Fold
        cmp Exts + 1,x
        bne @next
        lda work - 1,y
        jsr Fold
        cmp Exts + 2,x
        bne @next
        clc
        rts
@next:  inx
        inx
        inx
        cpx #EXTS_LEN
        bcc @try
@no:    sec
        rts

; SameImg: C clear when work (the image's path) and ibuf name the same
; file, letters compared without case.
SameImg:
        ldy #$FF
@c:     iny
        lda work,y
        jsr Fold
        sta tmp
        lda ibuf,y
        jsr Fold
        cmp tmp
        bne @no
        lda tmp
        bne @c
        clc
        rts
@no:    sec
        rts

; Fold: A in lower case when it is a letter (ASCII, as the Ultimate's
; paths). X, Y kept.
Fold:   cmp #'A'
        bcc @end
        cmp #'Z' + 1
        bcs @end
        ora #$20
@end:   rts

Exts:           .byte "d64", "d71", "d81", "dnp"
EXTS_LEN        = * - Exts
drvPath:        .byte "/a", 0
drv:            .byte 0
segAt:          .byte 0
segEnd:         .byte 0
tmp:            .byte 0
ibuf:           .res INFO_MAX
