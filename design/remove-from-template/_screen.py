# Assemble the artifact page: shared chrome + the three screens.
import io

GRIP = '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M3.5 6h13M3.5 10h13M3.5 14h13"/></svg>'
CHEV = '<svg class="rp-chev" viewBox="0 0 20 20" fill="none" stroke="#5C5C6E" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 5l5 5-5 5"/></svg>'
CHEV_DOWN = '<svg class="rp-chev" style="transform: rotate(90deg)" viewBox="0 0 20 20" fill="none" stroke="#5C5C6E" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 5l5 5-5 5"/></svg>'
FOLDER = '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6.5A1.5 1.5 0 0 1 4.5 5h3l1.5 2h6.5A1.5 1.5 0 0 1 17 8.5v6A1.5 1.5 0 0 1 15.5 16h-11A1.5 1.5 0 0 1 3 14.5z"/></svg>'
PLUS = '<svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M10 4.5v11M4.5 10h11"/></svg>'
LINK = '<svg width="19" height="19" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8.6 11.4a3.3 3.3 0 0 0 4.7 0l2-2a3.3 3.3 0 0 0-4.7-4.7l-1 1"/><path d="M11.4 8.6a3.3 3.3 0 0 0-4.7 0l-2 2a3.3 3.3 0 0 0 4.7 4.7l1-1"/></svg>'
NOTE = '<svg width="19" height="19" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3.5" y="3.5" width="13" height="13" rx="3"/><path d="M6.6 8h6.8M6.6 11h6.8M6.6 14h4"/></svg>'
TRASH = '<svg width="19" height="19" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6h12"/><path d="M8 6V4.4h4V6"/><path d="M5.6 6l.8 9.2a1.5 1.5 0 0 0 1.5 1.4h4.2a1.5 1.5 0 0 0 1.5-1.4L14.4 6"/></svg>'
DUP = '<svg width="17" height="17" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><rect x="6.5" y="6.5" width="10" height="10" rx="2.2"/><path d="M13.5 4.5A2 2 0 0 0 11.7 3.5H5.5a2 2 0 0 0-2 2v6.2a2 2 0 0 0 1 1.8"/></svg>'
XMARK = '<svg width="13" height="13" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M5.5 5.5l9 9M14.5 5.5l-9 9"/></svg>'

def card(name, summary, style=""):
    return f'''<div class="rp-card"{style}><div class="rp-cardhead">
  <div class="rp-grip">{GRIP}</div>
  <div class="rp-exmeta"><div class="rp-exname">{name}</div><div class="rp-exsum">{summary}</div></div>
  {CHEV}
</div></div>'''

def nav():
    return f'''<div class="rp-statusspace"></div>
<div class="rp-nav">
  <div class="rp-navside">Cancel</div>
  <div class="rp-navtitle">Edit Template</div>
  <div class="rp-navside rp-bold">Save</div>
</div>'''

def namesection():
    return f'''<div class="rp-stack8">
  <div class="rp-eyebrow">TEMPLATE NAME</div>
  <div class="rp-namefield">Push Day A</div>
  <div class="rp-folderrow">{FOLDER}<span>Folder</span><span class="rp-grow"></span><span class="rp-foldernone">None</span>{CHEV}</div>
</div>'''

def exhead():
    return '''<div class="rp-exhead"><div class="rp-eyebrow">EXERCISES</div><div class="rp-count">4 exercises · 16 sets</div></div>'''

def addex():
    return f'<div class="rp-addex">{PLUS}Add Exercise</div>'

MENU = f'''<div class="rp-menurow"><span class="rp-grow">Superset with…</span>{LINK}</div>
<div class="rp-hair"></div>
<div class="rp-menurow"><span class="rp-grow">Add note</span>{NOTE}</div>
<div class="rp-section"></div>
<div class="rp-menurow rp-destructive"><span class="rp-grow">Remove from Template</span>{TRASH}</div>'''

def setrow(badge, warm, lo, hi, rir, rircolor):
    bstyle = 'background: rgba(201,123,90,0.14); color: #C97B5A' if warm else 'background: #262630; color: #EAEAEF'
    return f'''<div class="rp-setrow">
  <div class="rp-badge" style="{bstyle}">{badge}</div>
  <div class="rp-reps"><div class="rp-field rp-grow">{lo}</div><div class="rp-dash">–</div><div class="rp-field rp-grow">{hi}</div></div>
  <div class="rp-field rp-rir" style="color: {rircolor}">{rir}</div>
  <div class="rp-grow"></div>
  <div class="rp-iconbtn" style="background: #262630; color: #5C5C6E">{DUP}</div>
  <div class="rp-iconbtn" style="background: rgba(224,85,85,0.08); color: #E05555">{XMARK}</div>
</div>'''

EXPANDED = f'''<div class="rp-card">
  <div class="rp-cardhead">
    <div class="rp-grip">{GRIP}</div>
    <div class="rp-exmeta"><div class="rp-exname">Barbell Bench Press</div><div class="rp-exsum">2 warmup · 3 working · 6-8 reps · RIR 2</div></div>
    {CHEV_DOWN}
  </div>
  <div class="rp-divider"></div>
  <div class="rp-expanded">
    <div class="rp-setlist">
      <div class="rp-colhead-row">
        <div class="rp-colhead rp-c-set">SET</div>
        <div class="rp-colhead rp-c-rep">REP RANGE</div>
        <div class="rp-colhead rp-c-rir">RIR</div>
        <div class="rp-grow"></div>
      </div>
      {setrow("W1", True, 10, 12, 4, "#A0B83C")}
      {setrow("W2", True, 8, 8, 4, "#A0B83C")}
      {setrow("1", False, 6, 8, 2, "#E89B3E")}
      {setrow("2", False, 6, 8, 2, "#E89B3E")}
      {setrow("3", False, 6, 8, 1, "#E07040")}
    </div>
    <div class="rp-addsets">
      <div class="rp-btn-warm">＋ Warmup</div>
      <div class="rp-btn-work">＋ Working Set</div>
      <div class="rp-btn-more">More<svg width="9" height="9" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 8l5 5 5-5"/></svg></div>
    </div>
    <div class="rp-restrow">
      <div class="rp-restlabel">Rest Time</div><div class="rp-grow"></div>
      <div class="rp-restgroup"><div class="rp-restfield">180</div><div class="rp-restsec">sec</div></div>
    </div>
  </div>
</div>'''

# ---- Screen 1: long press ----
screen1 = f'''<div class="rp-screen">
  <div class="rp-under">
    {nav()}
    <div class="rp-body">
      {namesection()}
      <div class="rp-stack10">
        {exhead()}
        {card("Barbell Bench Press", "2 warmup · 3 working · 6-8 reps · RIR 2")}
        <div class="rp-card rp-ghost"><div class="rp-cardhead rp-hollow"></div></div>
        {card("Cable Fly", "3 working · 12-15 reps · RIR 1")}
        {card("Overhead Press", "1 warmup · 4 working · 5-7 reps · RIR 2")}
      </div>
      {addex()}
    </div>
  </div>
  <div class="rp-scrim"></div>
  <div class="rp-lifted">
    <div class="rp-cardhead">
      <div class="rp-grip">{GRIP}</div>
      <div class="rp-exmeta"><div class="rp-exname">Incline Dumbbell Press</div><div class="rp-exsum">3 working · 8-10 reps · RIR 2</div></div>
      {CHEV}
    </div>
  </div>
  <div class="rp-menu" style="top: 419px; left: 16px">{MENU}</div>
</div>'''

# ---- Screen 2: confirmation ----
screen2 = f'''<div class="rp-screen">
  <div class="rp-under rp-under-soft">
    {nav()}
    <div class="rp-body">
      {namesection()}
      <div class="rp-stack10">
        {exhead()}
        {card("Barbell Bench Press", "2 warmup · 3 working · 6-8 reps · RIR 2")}
        {card("Incline Dumbbell Press", "3 working · 8-10 reps · RIR 2", ' style="border-color: rgba(255,255,255,0.12)"')}
        {card("Cable Fly", "3 working · 12-15 reps · RIR 1")}
        {card("Overhead Press", "1 warmup · 4 working · 5-7 reps · RIR 2")}
      </div>
      {addex()}
    </div>
  </div>
  <div class="rp-scrim rp-scrim-heavy"></div>
  <div class="rp-alert">
    <div class="rp-alertbody">
      <div class="rp-alerttitle">Remove from Template?</div>
      <div class="rp-alertmsg">This will remove Incline Dumbbell Press and its 3 sets from this template.</div>
    </div>
    <div class="rp-hair-strong"></div>
    <div class="rp-alertbtns">
      <div class="rp-alertbtn rp-alertcancel">Cancel</div>
      <div class="rp-vhair"></div>
      <div class="rp-alertbtn rp-alertremove">Remove</div>
    </div>
  </div>
</div>'''

# ---- Screen 3: same menu from the More button ----
screen3 = f'''<div class="rp-screen">
  <div class="rp-under">
    {nav()}
    <div class="rp-body">
      {namesection()}
      <div class="rp-stack10">
        {exhead()}
        {EXPANDED}
      </div>
    </div>
  </div>
  <div class="rp-scrim"></div>
  <div class="rp-menu" style="top: 614px; left: 112px">{MENU}</div>
</div>'''

open("_screens.html", "w").write(screen1 + "\n<!--SPLIT-->\n" + screen2 + "\n<!--SPLIT-->\n" + screen3)
print("screens assembled")
