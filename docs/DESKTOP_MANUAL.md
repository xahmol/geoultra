# The GeoUltra desktop: user manual

GeoUltra's own desktop is what you see after the start: a file manager
for the GEOS drives and the Ultimate's own file system, and the place
programs are started from. It is still being built (docs/DESKTOP.md has
the plan and the state of the work); this manual describes what is
there now. GeoUltra always starts its own desktop (GEOS 2.0's deskTop
of the boot disk only starts when this one cannot).

## The screen

From top to bottom:

- **The menu bar**: the menus geos (GeoUltra info, settings, gush and
  the desk accessories), file, view, go and disk on the left, the date and time
  on the right (unless the theme or the clock setting leaves them out).
  Everything the toolbar does is in the menus too. GeoUltra info shows
  the version with the build's time stamp (v0.1.0-20261113-1310: version
  0.1.0, built 13 November 2026 at 13:10); its
  "splash" button shows the start picture again (a key or a click goes
  back). Drive E's desk accessories (geoFolder) come first in the geos
  menu, in every application's too, and always get a place.
- **The toolbar** (view > toolbar): buttons for the things done most,
  in four groups (see "The toolbar").
- **The sidebar** on the left: the drives, the Ultimate's roots, your
  favourite folders and your recent documents.
- **The list** on the right: the title bar with the current folder's
  name, the path line, and the folder's entries; a scroll strip on the
  right edge.
- **The status line** at the bottom: how many entries there are, how
  many are selected, and the free space on the drive.

The list is sorted: ".." (the folder above) first, then folders and
drives, then files, each group by name; upper and lower case are the
same for the order. (Folders with more than 384 entries keep the order
they have on disk.)

The small arrow at the right end of the path line turns the order
round (with two panes it is the first of the letters): pointing down,
the order is as chosen (names A to Z, the newest or the largest
first); pointing up, it is reversed. Folders and ".." stay first. In
the detailed view, a click on "Size" or "Date" sorts by that column, a
second click reverses it, and a third goes back to names; the column
the list is sorted by is shown in bold. The order is kept in
SETTINGS.INI (`sort=`, with a "-" in front when reversed).

## Views

view > view chooses how the list shows the entries (the toolbar's view
button goes through them in turn):

- **list**: a small icon and the name, one entry a row;
- **icons**: a grid of large icons with the name under each (5 columns,
  6 with the narrow sidebar). GEOS files show their own icon from their
  file header; folders, drives, plain files and disk images show
  GeoUltra's own;
- **detailed**: the list with the size and the date (GEOS files) beside
  each name.

## Two panes

view > two panes (C=P, or the toolbar's button between view and
refresh) shows two folders side by side, the sidebar hidden. Each pane
has its own folder, list, selection, scroll strip and half of the status
line (its entries, or the number selected, and its drive's free space);
the active pane's path line is inverted, and the menus, keys and toolbar act on it. A
click in a pane, or C=SPACE, makes it the active one. Each path line
ends in the drive letters A B C D E (the drives with an image, and E),
the pane's own drive marked; a click on one opens that drive in the
active pane (in the other pane: a first click makes it active); U
lists the Ultimate's roots (sd, usb0 ...). A click on the path text
opens a list of all places: the drives, the Ultimate's roots and your
favourites (with one list, a click on the path goes to that part of it). The panes show the
list or the icon view (the detailed view's columns do not fit). The
same keys and menu switch back to one list, with the view from before.
Copying between the panes: "copy to other" (C=T) and "move to other"
(C=M) in the file menu and the context menu put the selection into the
other pane's folder (they use the clipboard: it holds those entries
afterwards); or copy (or cut) in one pane and paste in the other.

**Drag and drop:** press on a selected entry and move the mouse with
the button held: the selection is dragged (its icon follows the
pointer). Released over the other pane, it goes into that pane's
folder: moved on the same drive, copied to another drive. Released
over a folder in the same list (one that is not part of the
selection), it is moved into that folder; while you drag, the folder or
sidebar line the selection would go into is shown inverted (not in the
icon view). Released over a drive or a
favourite in the sidebar (with one list), it goes into that drive's
top folder or that favourite folder: moved on the same drive, copied to
another. Hold C= while releasing to copy instead of move (or move
instead of copy). Folders are taken with everything in them.

## Moving around

- **Mouse**: a click on an entry selects it (the others no longer); C=
  and a click adds it or takes it away again; SHIFT and a click selects
  everything from the cursor to it. A double click opens the entry.
- **Keys**: cursor up and down move the cursor (C= held: the selection
  grows with it), HOME goes to the first entry, RETURN opens the entry
  under the cursor, cursor left goes up a folder; C= and cursor left or
  right go back or forward through the folders visited.
- **The go menu**: back, forward, up, root (all drives), home
  (GeoUltra's folder on the Ultimate), top and end.
- **Sidebar**: a click on a drive or an Ultimate root goes there; a
  click on a favourite goes to that folder; a click on a recent document
  opens it.
- **Path line**: a click on a part of the path goes to that folder.
- **Scroll strip**: the arrows move the list a row (in the icon view a
  row of icons), a click above or below the thumb a page.

Opening an entry:

- a **folder** or **drive**: goes into it;
- a GEOS **application** or **desk accessory**: starts it; a **document**
  starts the application it belongs to with it;
- a **disk image** on the Ultimate (`.d64`, `.d71`, `.d81`, `.dnp`):
  goes into it like a folder (see "Disk images and drives"); mounting
  it on a drive is in the context menu and on the toolbar;
- any **other file on the Ultimate**: is not opened (see "Drives: what
  works where").

## Files and folders

All in the file menu, with their keys:

| Action | Key | |
| --- | --- | --- |
| open | C=O | as a double click |
| info | C=I | see below |
| copy | C=C | the selected entries (or the one under the cursor) onto the clipboard |
| cut | C=X | the same, to be moved |
| paste | C=V | copies (or moves) the clipboard's entries into the current folder; asks before replacing a file (Yes, Yes to all, No) |
| delete | DEL | asks first; a folder with everything in it asks once more |
| rename | C=R | |
| new folder | C=N | on drives with folders (native drives, 1581 partitions, the Ultimate) |
| select all | C=A | every entry but ".." |
| favourite | C=F | the current folder (or the selected folder) into the sidebar's favourites (up to 4; the oldest goes) |

GeoUltra's shell, gush, is in the geos menu (C=G, and the toolbar's
last button): it takes the desktop's place (docs/GUSH_MANUAL.md).

Folders are copied, moved and deleted with everything in them. A long
copy shows its progress on the status line; RUN/STOP stops it.

**The right mouse button** opens a menu at the pointer with open, copy,
cut, paste, rename, delete, info, favourite and new folder. Over an
entry that is not selected yet, it selects that entry first. A click on
an item does it; a click outside the menu, RUN/STOP, ESC or the right
button again closes it. (On a 1351 the right button is the one GEOS
programs do not use; the Ultimate 64's USB mouse works as one.)

**Info** (in that menu, and the toolbar's info button) shows the entry
under the cursor: its name, kind (for GEOS files their type:
application, document, desk accessory, font, printer or input driver
...), size, date and GEOS class. For files on the Ultimate it reads the
size, which the folder listing does not have.

## The toolbar

Under the menu bar, in five groups:

| Buttons | |
| --- | --- |
| back, forward, up, root | the folders visited before and after (the last 16), the folder above, `/` (all drives) |
| top, end | the first and the last entry |
| view, two panes, refresh | the next view; one list or two panes; the folder read again |
| new folder, info, select all, copy, paste, delete | as in the file menu; info as in the context menu |
| settings, gush | GeoUltra Settings (see "Settings"), GeoUltra's shell |

view > toolbar sets its height: **two lines** (framed buttons, the
default), **one line** (the icons alone, one more row for the list) or
**off**.

## Disk images and drives

Drives A to D hold disk images from the Ultimate (they are kept in the
REU while mounted, and changes are written back to the image file).
Mount an image from the context menu or the toolbar: choose the drive in
the dialog. The eject icon on a drive's line in the sidebar unmounts it
(after writing it back). Which images are mounted at the start is in
`GEOULTRA/MOUNTS.INI` (`A=/USB0/path/image.d81`, one line per drive).

Opening (double click, RETURN) an image on the Ultimate goes into it
like a folder, without mounting it: its files are listed, and they can
be copied in and out, renamed and deleted; changes are written to the
image file straight away. `..` leaves it again. It needs:

- an **empty drive letter** (A-D): the image borrows it for a moment
  for each step, unseen;
- **room in the REU** for the whole image (a D81 13 banks of 64 KB, a
  DNP one per track), beside the mounted drives;
- the image **not mounted**: a mounted one is opened through its drive.

Programs and documents inside an image cannot be started or opened
from there ("Mount the disk image to open it."): mount it, or copy them
to a drive first.

## Drives: what works where

| Kind of drive | What it is | Programs and documents | Folders | Writing |
| --- | --- | --- | --- | --- |
| A-D: D64, D71 | a 1541 or 1571 disk image | start and open | no | yes |
| A-D: D81 | a 1581 disk image | start and open | 1581 partitions act as folders | yes |
| A-D: DNP | a native (CMD) disk image (up to 16 MB as a format; the REU holds about 10 MB for all mounted drives together) | start and open | yes, nested | yes |
| E | GeoUltra's system drive in the cartridge (gush, geoFolder, the desktop, gush's commands) | start | yes | no: read-only |
| usb0, usb1, sd | the Ultimate's own file system (the USB sticks, the SD card) | **not** started or opened | yes | yes |

What this means in practice:

- **GEOS programs and documents only work on drives A-E.** On the
  Ultimate's file system a GEOS file is kept in CVT form (a single file
  holding the whole GEOS file); opening it there shows "Not opened
  here". Copy it to one of the drives A-D first.
- **Copying between them converts.** A GEOS file copied onto the
  Ultimate becomes `name.cvt`; a `.cvt` copied onto a GEOS drive becomes
  the GEOS file again. Plain CBM files get `.prg`, `.seq` or `.usr` on
  the Ultimate and lose it again on the way back. gush's `cp` does the
  same.
- **Disk images on the Ultimate** can be gone into like folders (their
  files copied in and out, renamed, deleted); to start their programs or
  open their documents, mount them on A-D.
- **Sizes**: the Ultimate's listings give no sizes, so the detailed
  view leaves them empty for files there; Info shows a file's size.
- **Real disk drives** on the serial bus are not supported yet.

## Tasks

C= + RUN/STOP, in the desktop or in any application, opens the task
list: each running task (its application's name; the current one with
a "*"), "new task" (the current one is kept as it is and a fresh
desktop starts) and "close task" (the current one ends; the last one
stays). Cursor up and down and RETURN, or a click, choose; RUN/STOP or
a click outside closes the list. The status line shows the number of
tasks at its right end; a click there opens the same list. "open in new
task" (C=W, in the file menu and the context menu) opens the entry
under the cursor in a new task: a fresh desktop that opens it there,
while this one waits as it is. Each task keeps its own memory in the
REU, and hibernation keeps them all: after a power cycle every task
is back, in the one you left. A
document open in one task is saved when you leave that task and cannot
be opened, deleted, renamed or moved in another task until it is closed
("It is open in another task.").

## Themes

view > theme chooses the look: **GeoUltra** (the default), **GEOS
classic**, **Flat**, **Detailed**, **Night**, **Mono**, and **Custom**
(to edit). Each is a text file in `GEOULTRA/THEMES` on the stick, one
line per part of the screen, in words, for example:

```
[theme]
name=Custom
border=light grey
desk=dark grey on light grey
menubar=clock, dark grey on light grey
sidebar=wide, dark grey on light grey
headings=inverted, white on light blue
titlebar=stripes, dark grey on light grey
rows=9
columns=name
icons=on, blue
selection=invert, white on blue
cursor=dotted, blue
scrollbar=arrows
status=on, white on grey
toolbar=dark grey on light grey
```

"X on Y" is X text on a Y background. The styles each part takes:
menubar plain or clock; sidebar wide or narrow; headings inverted, band,
underlined or plain; titlebar stripes, solid, line or none; rows 9 or 8;
columns name or detailed; icons on or off; selection invert, bar or
frame; cursor dotted, mark or underline; scrollbar arrows or thin;
status on or off. A file needs only the lines it changes. On an Ultimate
64 a theme may also set the 16 colours themselves: `palette=` and 16
RRGGBB values (black ... light grey), as in the Night theme's file. The
desktop's menus and dialogs take the menu bar's colours; programs and
desk accessories keep GEOS's own.

In the icon view the icons can be coloured by type: a theme's
`icons-apps=`, `icons-documents=`, `icons-accessories=`,
`icons-system=` (fonts, drivers, boot files), `icons-folders=` (folders
and drives) and `icons-ultimate=` lines each give a colour (on the
desk's background); a type without a line keeps the desk's colour.
`icons-bytype=off` switches them off for the theme, `iconcolours=off`
in `SETTINGS.INI` (Settings' Desktop page, "Icon colours") for every
theme. On Settings' Theme page they are one part, "icons by type": on
or off, the type's ink (or "none"), and the type chosen with [-] [+].

## Settings

The desktop keeps its settings in `GEOULTRA/SETTINGS.INI` on the stick
(written when you change them in the menus):

```
[desktop]
theme=GeoUltra
view=list            (list, icons, detailed)
clock=24             (24, 12, off)
toolbar=16           (16: two lines, 8: one line, off)
panes=1              (1: one list, 2: two panes)
iconcolours=off      (the icon view's colours by type off; on: the theme's)

[favourites]
/usb0/geoultra
```

`RECENT.INI` holds the recent documents. Other sections of
`SETTINGS.INI` belong to the system.

**GeoUltra Settings** (geos > settings, or the toolbar's settings
button; in gush: `"/e/GU Settings"`) changes these without editing the
file: a list of pages on the left, the page on the right, OK (save and
leave), Cancel (leave; it asks when something was changed) and Save
(save and stay). The **REU** page shows how the 16 MB are used (a
cell per 64 KB: the system, each drive, the file engine, the legacy
REU, free) and sets the REU old applications see (512 KB to 4 MB per
task) and the number of task slots, together at most 4 MB; they take
effect at the next start. The **Drives** page shows drives A-D with
their images: "choose" browses the Ultimate's folders for a disk image
and mounts it at once, "none" unmounts (asked first; changes are
written back), "long names on/off" switches long names for that drive,
a DNP's tracks [-] [+] with "resize" mounts it again at that size, and
"new image" makes an empty D64, D71, D81 or DNP (then offers to mount
it). The **Start** page lists the auto-exec files the cold start runs
before the desktop, in order (add through a browser of the drives,
remove, up, down); holding SHIFT at power-on skips them, C= skips
resuming a hibernated session. Its first page is **Desktop**: which desktop starts
(GeoUltra's or GEOS 2.0's), the view, the toolbar, the clock and two
panes, the sort order (name, date: newest first, size: largest first,
type; folders always first), what happens when a copied file is
already there (ask, replace, skip, or replace only an older one: GEOS
files carry dates) and whether deleting asks first (a folder with
things in it is always asked about); they take effect when the
desktop starts again (after OK). Two panes come back with both
folders: the one you worked in on the left.
**System**: the turbo (full speed, off, or a speed step chosen with
- and +, shown in MHz for both kinds of Ultimate 64; it changes at
once), the programs that run at 1 MHz (add... picks a program on
drives A-D; remove takes the selected one out) and how long the
system waits without input before it hibernates (off, 15 s, 30 s,
1 min, 5 min). **Time**: the time server (click the box to type it),
"now" to set the clock from it (it saves the settings first), the time
zone in quarter hours, summer time by the EU's rule or off, and the
date and time by hand (set..., typed as YYYY-MM-DD HH:MM). The server
also sets the clock at every start. **Pointer** chooses the mouse
pointer, a classic arrow, a large arrow, a hand or a crosshair, and its
colour (- and +, any of the 16); both change at once and stay at every
start. **Theme** edits the theme files: choose a theme with - and +
("use" makes it the desktop's, "copy" starts a new one from it), a part
of the screen with - and +, its style and its ink and paper from the
16 colours; the preview below shows the result. The part "palette"
(Ultimate 64) changes the 16 colours themselves: pick one, then its
red, green and blue with - and +; you see it at once; "none" goes back
to the Ultimate's own palette. Save or OK writes the theme file. The
pages Drives and REU follow; their plan is in docs/SETTINGS.md.

## Limits

- Folders with more than 384 entries are shown in the order on disk;
  a folder holds at most 2048 entries in the list.
- The icon view keeps the first 448 entries' icons in the REU; later
  ones are read again when shown.
