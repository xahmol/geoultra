; pdfscript.inc: what GU PDF (src/printer/pdf.s) and its scripts
; (pdfdata.s, the file "pdfdata" on drive E) share: the scripts' codes
; and the numbers they write. A script is PDF text with codes: a byte of
; 10 or from 32 on is text, a code (C_*) takes one argument byte, 0 ends
; it. Own code, 2026-11-16.

; vals: the numbers the scripts write, 4 bytes each (V_*)
V_PAGES         = 0             ; the document's pages written
V_PREV          = 4             ; the last xref's offset (/Prev)
V_XREF          = 8             ; this one's
V_CAT           = 12            ; the objects' offsets
V_TREE          = 16
V_IMG           = 20
V_CONT          = 24
V_PAGE          = 28
VALS            = 32

C_OBJ   = 1                     ; "n 0 obj\n", n the page's object (arg)
C_REF   = 2                     ; "n 0 R ", n the page's object (arg)
C_ONUM  = 3                     ; n, the page's object (arg)
C_AT    = 4                     ; vals + arg = pos (an object's offset)
C_ENTRY = 5                     ; an xref line for vals + arg
C_NUM   = 6                     ; vals + arg in decimal
C_KIDS  = 7                     ; the pages' "n 0 R " (arg unused)
C_SUB   = 8                     ; the script Subs + arg (2 bytes each)
C_PAGE  = 9                     ; the page counted (arg unused)
