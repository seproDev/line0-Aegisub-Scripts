script_name="Move Along Path"
script_description=""
script_version="0.0.1"
script_author="line0"

local l0Common = require("l0.Common")
local LineCollection = require("a-mo.LineCollection")
local ASSTags = require("l0.ASSTags")
local Log = require("a-mo.Log")
local YUtils = require("YUtils")

function showDialog(sub, sel)
    local dlg = {
        {
            class="label",
            label="Select which tags are to be animated\nalong the path specified as a \\clip:",
            x=0, y=0, width=2, height=1,
        },
        {
            class="label",
            label="Tag                 ",
            x=0, y=1, width=1, height=1,
        },
        {
            class="label",
            label="Relative",
            x=1, y=1, width=1, height=1,
        },
        {
            class="checkbox",
            name="aniPos", label="\\pos",
            x=0, y=2, width=1, height=1, value=true
        },
        {
            class="checkbox",
            name="relPos", label="",
            x=1, y=2, width=1, height=1,
        },
        {
            class="checkbox",
            name="aniFrz", label="\\frz",
            x=0, y=3, width=1, height=1, value=true
        }
    }

    local btn, res = aegisub.dialog.display(dlg)
    if btn then process(sub,sel,res) end
end

function getLengthWithinBox(w, h, angle)
    angle = angle%180
    angle =  math.rad(angle>90 and 180-angle or angle)

    if w==0 or h==0 then return 0
    elseif angle==0 then return w
    elseif angle==90 then return h end

    local A = math.atan2(h,w)
    if angle==A then return YUtils.math.distance(w,h)
    else
        local a,b = angle<A and w or h, angle<A and math.tan(angle)*w or h/math.tan(angle)
        return YUtils.math.distance(a,b)
    end
end

function process(sub,sel,res)
    aegisub.progress.task("Processing...")

    local lines = LineCollection(sub,sel)

    -- get total duration of the fbf lines
    local totalDuration = -lines.lines[1].duration
    lines:runCallback(function(lines, line)
        totalDuration = totalDuration + line.duration
    end)

    local startDist, metricsCache, path, posOff, angleOff, totalLength = 0, {}
    local finalLines = LineCollection(sub)
    local alignOffset = {
        [0] = function(w,a) return math.cos(math.rad(a))*w end,    -- right
        [1] = function() return 0 end,                             -- left
        [2] = function(w,a) return math.cos(math.rad(a))*w/2 end,  -- center
        [3] = function(w,a) return math.sin(math.rad(a))*w end,    -- bottom   -- actually, don't care about vertical alignment because text is rotated
        [4] = function(w,a) return math.sin(math.rad(a))*w/2 end,  -- middle
        [5] = function() return 0 end                              -- top
    }

    lines:runCallback(function(lines, line, i)
        data = ASS.parse(line)
        if i==1 then -- get path data and relative position/angle from first line
            path = data:getTags("clip_vect")[1]
            data:removeTags("clip_vect")
            angleOff, posOff = path:getAngleAtLength(0), path.commands[1]:get()
            totalLength = path:getLength()
        end

        -- split line by characters
        local charLines, charOff = data:splitAtIntervals(1,4,false), 0
        for i=1,#charLines do
            local charData = charLines[i].ASS
            -- calculate new position and angle
            local __atLength = startDist+charOff
            local targetPos, angle = path:getPositionAtLength(startDist+charOff), path:getAngleAtLength(startDist+charOff)
            
            if not targetPos then
                break   -- stop if he have reached the end of the path
            end
            -- get tags effective as of the first section (we know there won't be any tags after that)
            local effTags = charData.sections[1]:getEffectiveTags(true,true).tags

            -- calculate final rotation and write tags
            if res.aniFrz then
                effTags.angle:set(angle)
                charData:removeTags("angle")
                charData:insertTags(effTags.angle,1)
            end 

            -- get font metrics
            local width = charData:getTextExtents()

            -- calculate how much "space" the character takes up on the line
            -- and determine the distance offset for the next character
            -- this currently only uses horizontal metrics so it breaks if you disable rotation animation
            local w, h = width, width  
            charOff = charOff + getLengthWithinBox(w, h, angle) 

            __tpos = targetPos:copy()
            if res.aniPos then
                local an = effTags.align:get()
                targetPos:add(alignOffset[an%3](w,angle), alignOffset[an%3](h,angle+90))
                local pos = effTags.position
                if res.relPos then
                    pos:add(targetPos:sub(posOff))
                else pos:set(targetPos) end
                charData:removeTags("position")
                charData:insertTags(pos,1)
            end

            charData:commit()

            -- debug logging
            charData:insertSections(ASSLineCommentSection(string.format("Width: %d Angle: %d charOffAfter: %d atLength: %d posAtLength: (%d, %d)",
            width, angle, charOff, __atLength, __tpos:get())))
            charData:commit()
            finalLines:addLine(charLines[i])
        end
        startDist = startDist + (totalLength * (line.duration/totalDuration))
        aegisub.progress.set(i*100/#lines.lines)
    end, true)
    lines:deleteLines()
    finalLines:insertLines()
end

aegisub.register_macro(script_name, script_description, showDialog)
    
    