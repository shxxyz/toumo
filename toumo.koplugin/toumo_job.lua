-- A child renders from its private copy of crengine. It returns the finished
-- stencil through shared memory without touching the reader or its display.
local BB = require("ffi/blitbuffer")
local ffi = require("ffi")
local bit = require("bit")
local util = require("ffi/util")
local time = require("ui/time")
require("ffi/posix_h")
local C = ffi.C
local Job = {}
Job.__index = Job

local function reap(pid, flags)
    local result
    repeat
        result = C.waitpid(pid, nil, flags)
    until result >= 0 or ffi.errno() ~= C.EINTR
    return result ~= 0
end

function Job.start(page, width, height, render)
    local bytes = width * height * 2
    local mapping = C.mmap(
        nil,
        bytes + 1,
        bit.bor(C.PROT_READ, C.PROT_WRITE),
        bit.bor(C.MAP_SHARED, C.MAP_ANONYMOUS),
        -1,
        0
    )
    if mapping == ffi.cast("void *", -1) then
        return nil
    end
    local data = ffi.cast("uint8_t *", mapping)
    local ok, pid = pcall(util.runInSubProcess, function()
        local mask = render()
        ffi.copy(data, mask.data, bytes)
        data[bytes] = 1
    end)
    if not ok or not pid then
        C.munmap(mapping, bytes + 1)
        return nil
    end
    return setmetatable(
        {
            page = page,
            pid = pid,
            data = data,
            bytes = bytes,
            width = width,
            height = height,
            started = time.now(),
        },
        Job
    )
end

function Job:release()
    C.munmap(self.data, self.bytes + 1)
    self.data = nil
end

function Job:cancel()
    if not reap(self.pid, C.WNOHANG) then
        -- This job runs only crengine/raster code; it never starts children.
        C.kill(self.pid, 9)
        reap(self.pid, 0)
    end
    self:release()
end

-- A stalled render on a malformed/very complex page should not hang a tap.
-- On timeout the caller paints its available layers once and keeps that frame.
function Job:collect(wait)
    local deadline = wait and time.now() + time.s(1.5)
    while not reap(self.pid, C.WNOHANG) do
        if (deadline and time.now() >= deadline) or time.now() - self.started >= time.s(5) then
            self:cancel()
            return true, nil
        end
        if not wait then
            return false
        end
        C.usleep(3000)
    end
    local mask
    if self.data[self.bytes] == 1 then
        mask = BB.new(self.width, self.height, BB.TYPE_BB8A)
        ffi.copy(mask.data, self.data, self.bytes)
    end
    self:release()
    return true, mask
end

return Job
