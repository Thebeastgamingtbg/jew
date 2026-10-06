-- Original streaming player, inspired by JamnedZ/badapple_cctweaked.
local args = {...}
local base = args[1] or 'rickroll'
local scale = tonumber(args[2]) or 0.5
local volume = tonumber(args[3]) or 1
local function open(path, mode)
  local h, err = fs.open(path, mode)
  assert(h, err or ('Missing '..path))
  return h
end
local mh = open(base..'.meta', 'r')
local meta = textutils.unserializeJSON(mh.readAll()); mh.close()
assert(meta and meta.width and meta.height and meta.fps and meta.frames, 'Invalid metadata')
local monitor = peripheral.find('monitor')
local screen = monitor or term.current()
local speaker = peripheral.find('speaker')
assert(speaker, 'Attach a speaker')
assert(screen.isColor(), 'Use an advanced computer or advanced monitor')
local oldScale = monitor and monitor.getTextScale()
if monitor then monitor.setTextScale(scale) end
local sw, sh = screen.getSize()
if sw < meta.width or sh < meta.height then
  if monitor then monitor.setTextScale(oldScale) end
  error('Screen needs at least '..meta.width..' x '..meta.height..' characters')
end
local video = open(base..'.nfpa', 'r')
local audio = open(base..'.dfpwm', 'rb')
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
    local chunk = audio.read(6000)
    if not chunk then break end
    local buffer = decode(chunk)
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
      rows[row] = video.readLine()
      assert(rows[row] and #rows[row]==meta.width, 'Truncated video')
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
