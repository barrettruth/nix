local expected = "REPLACE_WITH_ERROR_TEXT"
local saw_expected = false

local function mark(name, value)
	io.stderr:write(("MARK:%s=%s\n"):format(name, tostring(value)))
	io.stderr:flush()
end

local function capture(label, ok, err)
	mark(label .. "_ok", ok)
	if not ok then
		local message = tostring(err)
		mark(label .. "_error", message:gsub("\n", "\\n"))
		if message:find(expected, 1, true) then
			saw_expected = true
		end
	end
end

-- Issue-specific setup/actions begin.
mark("scenario_started", true)

-- Replace this block with the smallest script strategy that exercises the
-- reported path. Emit MARK lines for every critical path assumption.

-- Issue-specific setup/actions end.

local messages = vim.api.nvim_exec2("messages", { output = true }).output
if messages:find(expected, 1, true) then
	saw_expected = true
end
for line in messages:gmatch("[^\n]+") do
	if line:find(expected, 1, true) then
		mark("captured_message", line:gsub("\n", "\\n"))
	end
end

mark("saw_expected", saw_expected)
if saw_expected then
	mark("repro_status", "reproduced")
	os.exit(1)
end

mark("repro_status", "not_reproduced")
