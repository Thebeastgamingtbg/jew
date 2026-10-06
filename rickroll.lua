-- Small Rickroll: packed black/white video plus 24 kHz DFPWM audio.
local repo = "https://raw.githubusercontent.com/Thebeastgamingtbg/jew/main/"
local files = {{"rickroll.bwv",102240},{"rickroll24.dfpwm",639000}}
local needed = 0
for _, item in ipairs(files) do
  if fs.exists(item[1]) then
    assert(fs.getSize(item[1]) == item[2],
      item[1].." is incomplete or incompatible. Delete it and run again.")
  else needed = needed + item[2] end
end
local free = fs.getFreeSpace(".")
assert(free == "unlimited" or free >= needed + 4096,
  "Not enough storage. Delete the old rickroll.nfpa and rickroll.dfpwm, then retry.")
for _, item in ipairs(files) do
  local path = item[1]
  if not fs.exists(path) then
    print("Downloading "..path.."...")
    local response, err = http.get(repo..path, nil, true)
    assert(response, err or "Download failed")
    local output, openErr = fs.open(path, "wb")
    if not output then response.close(); error(openErr) end
    local ok, writeErr = pcall(function()
      while true do
        local chunk = response.read(8192)
        if not chunk then break end
        output.write(chunk)
      end
    end)
    response.close(); output.close()
    if not ok then fs.delete(path); error(writeErr) end
    if fs.getSize(path) ~= item[2] then
      fs.delete(path)
      error("Download size mismatch. Upload the converted file to your GitHub repository.")
    end
  end
end
-- Original streaming player, inspired by JamnedZ/badapple_cctweaked.
local args = {...}
local base = 'rickroll'
local scale = tonumber(args[1]) or 0.5
local volume = tonumber(args[2]) or 1
local function open(path, mode)
  local h, err = fs.open(path, mode)
  assert(h, err or ('Missing '..path))
  return h
end
local meta = {width=32, height=12, fps=10, frames=2130}
assert(meta and meta.width and meta.height and meta.fps and meta.frames, 'Invalid metadata')
local monitor = peripheral.find('monitor')
local screen = monitor or term.current()
local speaker = peripheral.find('speaker')
assert(speaker, 'Attach a speaker')
-- Black and white playback also supports standard monitors.
local oldScale = monitor and monitor.getTextScale()
if monitor then monitor.setTextScale(scale) end
local sw, sh = screen.getSize()
if sw < meta.width or sh < meta.height then
  if monitor then monitor.setTextScale(oldScale) end
  error('Screen needs at least '..meta.width..' x '..meta.height..' characters')
end
local video = open(base..'.bwv', 'rb')
local audio = open(base..'24.dfpwm', 'rb')
local decode = require('cc.audio.dfpwm').make_decoder()
local start
local function now() return os.epoch('utc') / 1000 end
local function waitUntil(t)
  local delay = t - now()
  if delay > 0 then sleep(delay) end
end
local function playAudio()
  speaker.stop()
  local samples = 0
  while true do
    local chunk = audio.read(3000)
    if not chunk then break end
    local decoded = decode(chunk)
    local buffer = {}
    -- Speakers require 48 kHz: duplicate each 24 kHz sample.
    for i=1,#decoded do
      buffer[2*i-1] = decoded[i]
      buffer[2*i] = decoded[i]
    end
    while not speaker.playAudio(buffer, volume) do
      os.pullEvent('speaker_audio_empty')
    end
    if not start then start = now() end
    samples = samples + #buffer
  end
  if start then waitUntil(start + samples / 48000 + 0.1) end
end
local function playVideo()
  while not start do sleep(0) end
  screen.setBackgroundColor(colors.black); screen.clear()
  local x = math.floor((sw-meta.width)/2)+1
  local y = math.floor((sh-meta.height)/2)+1
  local blanks, fg = string.rep(' ',meta.width), string.rep('0',meta.width)
  for frame=1,meta.frames do
    local rows = {}
    for row=1,meta.height do
      local packed = video.read(4)
      assert(packed and #packed==4, 'Truncated video')
      local pixels = {}
      for byte=1,4 do
        local value = string.byte(packed,byte)
        for bit=7,0,-1 do
          pixels[#pixels+1] = bit32.band(value,2^bit) ~= 0 and '0' or 'f'
        end
      end
      rows[row] = table.concat(pixels)
    end
    local target = start + (frame-1)/meta.fps
    waitUntil(target)
    -- Skip late frames to keep the picture aligned to audio.
    if now() < target + 1/meta.fps or frame==meta.frames then
      for row=1,meta.height do
        screen.setCursorPos(x,y+row-1)
        screen.blit(blanks,fg,rows[row])
      end
    end
    if frame % 20 == 0 then sleep(0) end
  end
end
local ok, err = pcall(function() parallel.waitForAll(playAudio,playVideo) end)
video.close(); audio.close(); speaker.stop()
if monitor then monitor.setTextScale(oldScale) end
if not ok then error(err,0) end
print('Playback complete.')
