-- Hexion: MAME's state at frame_done (the start of the vertical blank, where MAME has just drawn the frame), as the system bench writes
-- the core's (sim/tb_top.sv): ram_<f>.bin = the work RAM (a000-bfff), VRAM bank 0, VRAM bank 1 (8 KB each), then 16 bytes of the
-- board's registers (MAME's are not reachable from Lua: zeros); snap_<f>.png = MAME's snapshot of the frame.
--   DUMPFRAMES=<f,f,...> or DUMPFROM / DUMPTO / DUMPEVERY;  DUMPDIR=<dir>;  NOSNAP=1 (no snapshots);  LAST=<f> (the frame to stop at)
--   SCHED=play|test       the scripted inputs, the same as the system bench's (sim/tb_hexion.cpp sched_in())
local mach = manager.machine
local sp   = mach.devices[":maincpu"].spaces["program"]
local scr  = mach.screens[":screen"]
local FR, LAST = {}, 0
for n in string.gmatch(os.getenv("DUMPFRAMES") or "", "%d+") do FR[tonumber(n)] = true; if tonumber(n) > LAST then LAST = tonumber(n) end end
local FROM, TO, EVERY = tonumber(os.getenv("DUMPFROM") or "-1"), tonumber(os.getenv("DUMPTO") or "-1"), tonumber(os.getenv("DUMPEVERY") or "1")
if TO > LAST then LAST = TO end
if os.getenv("LAST") then LAST = tonumber(os.getenv("LAST")) end
local DIR = os.getenv("DUMPDIR") or "."
local SCHED = os.getenv("SCHED")
if SCHED == "" then SCHED = nil end
local NOSNAP = os.getenv("NOSNAP") == "1"

local function field(port, name)
  local p = mach.ioport.ports[port]
  for n, f in pairs(p.fields) do if n == name then return f end end
end
local F = {
  coin1 = field(":SYSTEM", "Coin 1"), start1 = field(":P1", "1 Player Start"),
  b1 = field(":P1", "P1 Button 1"), b2 = field(":P1", "P1 Button 2"),
  left = field(":P1", "P1 Left"), right = field(":P1", "P1 Right"), down = field(":P1", "P1 Down"),
}

-- the schedule (tb_hexion.cpp's sched_in); SCHED=test sets the service mode DIP (the bench: +DSW=FF4FFB) and opens the test menu's
-- MASK ROM CHECK, which reads the tile ROMs through the f500 window
if SCHED == "test" then mach.ioport.ports[":DSW3"].fields["Service Mode"].user_value = 0 end
local function sched(f)
  local p = {}
  if SCHED == "test" then
    for _, s in ipairs({400, 420, 440, 460}) do if f >= s and f < s + 6 then p.down = true end end
    p.start1 = (f >= 500 and f < 506)
    return p
  end
  p.coin1 = (f >= 300 and f < 306)
  p.start1 = (f >= 400 and f < 406)
  if SCHED == "play" and f >= 600 then
    p.b1    = ((f // 10) % 6 == 0)
    p.b2    = ((f // 10) % 6 == 3)
    p.left  = ((f // 45) % 4 == 1)
    p.right = ((f // 45) % 4 == 3)
    p.down  = ((f // 30) % 5 == 4)
  end
  return p
end

local vram0 = mach.memory.shares[":vram0"]
local vram1 = mach.memory.shares[":vram1"]
local function dump(f)
  local t = {}
  for a = 0xa000, 0xbfff do t[#t + 1] = string.char(sp:read_u8(a)) end
  for a = 0, 0x1fff do t[#t + 1] = string.char(vram0:read_u8(a)) end
  for a = 0, 0x1fff do t[#t + 1] = string.char(vram1:read_u8(a)) end
  t[#t + 1] = string.rep("\0", 16)
  local fh = io.open(string.format("%s/ram_%d.bin", DIR, f), "wb"); fh:write(table.concat(t)); fh:close()
  if not NOSNAP then scr:snapshot(string.format("%s/snap_%d.png", DIR, f)) end
end

emu.register_frame_done(function()
  local f = scr:frame_number()
  if SCHED then
    local p = sched(f)
    for n, fld in pairs(F) do if fld then fld:set_value(p[n] and 1 or 0) end end
  end
  if FR[f] or (FROM >= 0 and f >= FROM and f <= TO and (f - FROM) % EVERY == 0) then dump(f) end
  if f >= LAST then mach:exit() end
end)
