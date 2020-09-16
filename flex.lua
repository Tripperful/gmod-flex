AddCSLuaFile()
if SERVER then return end

local FLEX_DIR_ROW            = 0 _G.FLEX_DIR_ROW = FLEX_DIR_ROW
local FLEX_DIR_COL            = 1 _G.FLEX_DIR_COL = FLEX_DIR_COL

local FLEX_FLOW_START         = 0 _G.FLEX_FLOW_START = FLEX_FLOW_START
local FLEX_FLOW_CENTER        = 1 _G.FLEX_FLOW_CENTER = FLEX_FLOW_CENTER
local FLEX_FLOW_END           = 2 _G.FLEX_FLOW_END = FLEX_FLOW_END
local FLEX_FLOW_STRETCH       = 3 _G.FLEX_FLOW_STRETCH = FLEX_FLOW_STRETCH

local FLEX_WRAP_NONE          = 0 _G.FLEX_WRAP_NONE = FLEX_WRAP_NONE
local FLEX_WRAP_BEFORE_SHRINK = 1 _G.FLEX_WRAP_BEFORE_SHRINK = FLEX_WRAP_BEFORE_SHRINK
local FLEX_WRAP_AFTER_SHRINK  = 2 _G.FLEX_WRAP_AFTER_SHRINK = FLEX_WRAP_AFTER_SHRINK


local FLEX_INTERP_LINEAR      = 0 _G.FLEX_INTERP_LINEAR = FLEX_INTERP_LINEAR
local FLEX_INTERP_SMOOTH      = 1 _G.FLEX_INTERP_SMOOTH = FLEX_INTERP_SMOOTH
local FLEX_INTERP_FADEIN      = 2 _G.FLEX_INTERP_FADEIN = FLEX_INTERP_FADEIN
local FLEX_INTERP_FADEOUT     = 3 _G.FLEX_INTERP_FADEOUT = FLEX_INTERP_FADEOUT

local interp = {
  [FLEX_INTERP_LINEAR] = function(x) return x end,
  [FLEX_INTERP_SMOOTH] = function(x) return 0.5 + math.sin((x - 0.5) * math.pi) / 2 end,
  [FLEX_INTERP_FADEIN] = function(x) return 1 + math.sin((x - 1) * math.pi * 0.5) end,
  [FLEX_INTERP_FADEOUT] = function(x) return math.sin(x * math.pi * 0.5) end,
}

local inf = 1 / 0

local function calcLine(items, crossFlow)
  local main = 0
  local mainSpace = 0
  local mainGap = 0
  local mainMB, mainMF = 0, 0
  local crossStart, crossEnd, crossTotal = inf, 0, 0
  local stretchCrossMB, stretchCrossMF = 0, 0
  for i, item in pairs(items) do
    item.targetMain = item:DesiredMain()
    item.targetCross = item:DesiredCross()
    mainGap = math.max(mainGap, item.mainMB)
    if i == 1 then
      mainGap = 0
      mainMB = item.mainMB
    end
    main = main + mainGap + item.targetMain
    mainSpace = mainSpace + mainGap
    mainGap = item.mainMF
    local flow = item.selfCrossFlow or crossFlow
    crossTotal = math.max(crossTotal, item.crossMB + item.targetCross + item.crossMF)
    if flow == FLEX_FLOW_START or flow == FLEX_FLOW_STRETCH then
      crossStart = math.min(crossStart, item.crossMB)
      crossEnd = math.max(crossEnd, item.crossMB + item.targetCross)
      if flow == FLEX_FLOW_STRETCH then
        stretchCrossMB = math.max(stretchCrossMB, item.crossMB)
        stretchCrossMF = math.max(stretchCrossMF, item.crossMF)
      end
    elseif flow == FLEX_FLOW_END then
      crossStart = math.min(crossStart, crossTotal - item.crossMF - item.targetCross)
      crossEnd = math.max(crossEnd, crossTotal - item.crossMF)
    elseif flow == FLEX_FLOW_CENTER then
      crossStart = math.min(crossStart, crossTotal / 2 - item.targetCross / 2)
      crossEnd = math.max(crossEnd, crossTotal / 2 + item.targetCross / 2)
    end
  end
  mainMF = mainGap
  local cross = crossEnd - crossStart
  local crossMB = math.max(crossStart, stretchCrossMB)
  local crossMF = math.max(crossTotal - crossEnd, stretchCrossMF)
  return
    main,
    mainSpace,
    mainMB,
    mainMF,
    cross,
    crossMB,
    crossMF
end

local function calcLines(items, dir, wrap, mainSize, mainPB, mainPF)
  if wrap == FLEX_WRAP_NONE then
    for i, item in pairs(items) do
      item:SetFlowDir(dir)
    end
    return {items}
  end
  local curLine
  local lines = {}
  local lineLen = 0
  local prevGap = mainPB
  for i, item in pairs(items) do
    if item.flex then
      item:SetFlowDir(dir)
      prevGap = math.max(prevGap, item.mainMB)
      local itemMainMin =
        wrap == FLEX_WRAP_AFTER_SHRINK and item.shrink > 0 and item.mainMin or
        item.main
      lineLen = lineLen + prevGap + itemMainMin
      prevGap = item.mainMF
      if not curLine or lineLen + math.max(prevGap, mainPF) > mainSize then
        curLine = {item}
        table.insert(lines, curLine)
        lineLen = math.max(mainPB, item.mainMB) + itemMainMin
        prevGap = item.mainMF
      else
        table.insert(curLine, item)
      end
    end
  end
  return lines
end

local function getGrowable(items)
  local growable = {}
  local totalGrow = 0
  for i, item in ipairs(items) do
    if item.targetMain < item.mainMax then
      table.insert(growable, item)
      totalGrow = totalGrow + item.grow
    end
  end
  return growable, totalGrow
end

local function getShrinkable(items)
  local shrinkable = {}
  local totalShrink = 0
  for i, item in ipairs(items) do
    if item.targetMain > item.mainMin then
      table.insert(shrinkable, item)
      totalShrink = totalShrink + item.shrink
    end
  end
  return shrinkable, totalShrink
end

local SCROLLX = vgui.RegisterTable({}, 'Panel')

function SCROLLX:Init()
  self:SetSize(8, 8)
end

function SCROLLX:Paint(w, h)
  local flex = self:GetParent()
  local pw = flex:GetWide()
  surface.SetDrawColor(0, 0, 0, 200)
  surface.DrawRect(0, 0, w, h)
  if self.dragging then
    local x, _ = flex:CursorPos()
    local scrollProgress = (x - self.clickOffset) / (pw - w)
    local clampedOffsetX = math.Clamp(
      Lerp(scrollProgress, flex.overflowXB, flex.overflowXF),
      flex.overflowXB,
      flex.overflowXF
    )
    if clampedOffsetX ~= flex.offsetX then
      flex.offsetX = clampedOffsetX
      flex:InvalidateLayout(true)
    end
  end
end

function SCROLLX:OnMousePressed(mcode)
  if mcode == MOUSE_LEFT then
    self.dragging = true
    self:MouseCapture(true)
    local x, _ = self:CursorPos()
    self.clickOffset = x
  end
end

function SCROLLX:OnMouseReleased(mcode)
  if self.dragging then
    self:MouseCapture(false)
    self.dragging = false
  end
end

local SCROLLY = vgui.RegisterTable({}, 'Panel')

function SCROLLY:Init()
  self:SetSize(8, 8)
end

function SCROLLY:Paint(w, h)
  local flex = self:GetParent()
  local ph = flex:GetTall()
  surface.SetDrawColor(0, 0, 0, 200)
  surface.DrawRect(0, 0, w, h)
  if self.dragging then
    local _, y = flex:CursorPos()
    local scrollProgress = (y - self.clickOffset) / (ph - h)
    local clampedOffsetY = math.Clamp(
      Lerp(scrollProgress, flex.overflowYB, flex.overflowYF),
      flex.overflowYB,
      flex.overflowYF
    )
    if clampedOffsetY ~= flex.offsetY then
      flex.offsetY = clampedOffsetY
      flex:InvalidateLayout(true)
    end
  end
end

function SCROLLY:OnMousePressed(mcode)
  if mcode == MOUSE_LEFT then
    self.dragging = true
    self:MouseCapture(true)
    local _, y = self:CursorPos()
    self.clickOffset = y
  end
end

function SCROLLY:OnMouseReleased(mcode)
  if self.dragging then
    self:MouseCapture(false)
    self.dragging = false
  end
end

local FLEX = vgui.Register('Flex', {
  bgColor = nil,
  w = 0, wMin = 0, wMax = inf,
  h = 0, hMin = 0, hMax = inf,
  wAuto = false, hAuto = false,
  dir = FLEX_DIR_ROW,
  mainFlow = FLEX_FLOW_START,
  crossFlow = FLEX_FLOW_START,
  selfCrossFlow = nil,
  lineFlow = FLEX_FLOW_START,
  wrap = FLEX_WRAP_NONE,
  grow = 0, shrink = 0,
  scrollX = true, scrollY = true,
  scrollSpeedX = 16, scrollSpeedY = 16,
}, 'Panel')

function FLEX:Init()
  self.flex = true
  self.offsetX, self.offsetY = 0, 0
  self.overflowXB, self.overflowXF = 0, 0
  self.overflowYB, self.overflowYF = 0, 0
  self:SetFlowDir(self.dir)
  self.scrollbarX = self:Add(SCROLLX)
  self.scrollbarY = self:Add(SCROLLY)
end

function FLEX:DesiredMain()
  return math.Clamp(self.main, self.mainMin, self.mainMax)
end

function FLEX:DesiredCross()
  return math.Clamp(self.cross, self.crossMin, self.crossMax)
end

function FLEX:GetItems()
  local items = {}
  for i, child in pairs(self:GetChildren()) do
    if child.flex and child:IsVisible() then
      table.insert(items, child)
    end
  end
  return items
end

function FLEX:Anim(duration, interpMethod, animTick, animEnd)
  local animId = tostring(self:GetTable()) .. tostring(animTick)
  local animStart = CurTime()
  local interpFunc = interp[interpMethod]
  hook.Add('Think', animId, function()
    local progress = math.Clamp((CurTime() - animStart) / duration, 0, 1)
    if IsValid(self) then
      animTick(interpFunc(progress))
    end
    if progress >= 1 then
      hook.Remove('Think', animId)
      if animEnd then
        animEnd()
      end
    end
    if IsValid(self) then
      self:InvalidateChildren(true)
    end
  end)
end

function FLEX:SetFlowDir(dir)
  local ml, mt, mr, mb = self:GetDockMargin()
  local pl, pt, pr, pb = self:GetDockPadding()
  self.ml, self.mt, self.mr, self.mb = ml, mt, mr, mb
  self.pl, self.pt, self.pr, self.pb = pl, pt, pr, pb
  if dir == FLEX_DIR_ROW then
    self.main, self.mainMin, self.mainMax = self.w, self.wMin, self.wMax
    self.cross, self.crossMin, self.crossMax = self.h, self.hMin, self.hMax
    self.mainMB, self.crossMB, self.mainMF, self.crossMF = ml or 0, mt or 0, mr or 0, mb or 0
    self.mainPB, self.crossPB, self.mainPF, self.crossPF = pl or 0, pt or 0, pr or 0, pb or 0
  elseif dir == FLEX_DIR_COL then
    self.main, self.mainMin, self.mainMax = self.h, self.hMin, self.hMax
    self.cross, self.crossMin, self.crossMax = self.w, self.wMin, self.wMax
    self.crossMB, self.mainMB, self.crossMF, self.mainMF = ml or 0, mt or 0, mr or 0, mb or 0
    self.crossPB, self.mainPB, self.crossPF, self.mainPF = pl or 0, pt or 0, pr or 0, pb or 0
  end
end

function FLEX:UpdateScrollbars()
  local w, h = self:GetSize()
  local clampedOffsetX = math.Clamp(self.offsetX, self.overflowXB, self.overflowXF)
  local clampedOffsetY = math.Clamp(self.offsetY, self.overflowYB, self.overflowYF)
  if clampedOffsetX ~= self.offsetX or clampedOffsetY ~= self.offsetY then
    self.offsetX = clampedOffsetX
    self.offsetY = clampedOffsetY
    self:InvalidateLayout(true)
    return
  end
  local overflowX = self.overflowXF - self.overflowXB
  if self.scrollX and overflowX > 1 then
    local scrollProgress = (self.offsetX - self.overflowXB) / overflowX
    local thumbSize = math.max(w * w / (w + overflowX), math.min(w / 2, 32))
    local maxThumbPos = w - thumbSize
    self.scrollbarX:SetSize(thumbSize, 8)
    self.scrollbarX:SetPos(maxThumbPos * scrollProgress, h - 8)
    self.scrollbarX:Show()
    self.scrollbarX:MoveToFront()
  else
    self.scrollbarX:Hide()
  end
  local overflowY = self.overflowYF - self.overflowYB
  if self.scrollY and overflowY > 1 then
    local scrollProgress = (self.offsetY - self.overflowYB) / overflowY
    local thumbSize = math.max(h * h / (h + overflowY), math.min(h / 2, 32))
    local maxThumbPos = h - thumbSize
    self.scrollbarY:SetSize(8, thumbSize)
    self.scrollbarY:SetPos(w - 8, maxThumbPos * scrollProgress)
    self.scrollbarY:Show()
    self.scrollbarY:MoveToFront()
  else
    self.scrollbarY:Hide()
  end
end

function FLEX:AutoSize()
  if self.wAuto then self.w = math.Clamp(self.cw, self.wMin, self.wMax) end
  if self.hAuto then self.h = math.Clamp(self.ch, self.hMin, self.hMax) end
end

function FLEX:PerformLayout(w, h)
  if not self:GetParent().flex then
    self:SetFlowDir(self.dir)
  end
  local isHorizontal = self.dir < FLEX_DIR_COL
  local main = isHorizontal and w or h
  local cross = isHorizontal and h or w
  local items = self:GetItems()
  local lines = calcLines(items, self.dir, self.wrap, main, self.mainPB, self.mainPF)
  local linesThickness = 0
  local lineGap
  for lineNumber, line in pairs(lines) do
    local lineMain, lineMainSpace
    lineMain,
    lineMainSpace,
    lineMainMB,
    lineMainMF,
    line.cross,
    line.crossMB,
    line.crossMF = calcLine(line, self.crossFlow)
    lineGap = lineGap and math.max(lineGap, line.crossMB) or 0
    linesThickness = linesThickness + lineGap + line.cross
    local mainSB, mainSF = math.max(self.mainPB, lineMainMB), math.max(self.mainPF, lineMainMF)
    local contentMainFill = lineMain - lineMainSpace
    local availableMainFill = main - mainSB - mainSF - lineMainSpace
    local remainder = availableMainFill - contentMainFill
    local flexResizeStart = CurTime()
    while math.floor(math.abs(remainder)) ~= 0 and CurTime() - flexResizeStart < 0.5 do
      local growing = remainder > 0
      local sizableItems, totalFactor
      if growing then
        sizableItems, totalFactor = getGrowable(line)
      else
        sizableItems, totalFactor = getShrinkable(line)
      end
      if totalFactor == 0 then break end
      local extent = remainder / totalFactor
      for i, item in pairs(sizableItems) do
        oldTargetMain = item.targetMain
        item.targetMain = math.Clamp(
          item.targetMain + extent * (growing and item.grow or item.shrink),
          item.mainMin,
          item.mainMax
        )
        remainder = remainder - (item.targetMain - oldTargetMain)
      end
    end
    line.remainder = remainder
  end
  local lineCount = #lines
  local contentCrossSB, contentCrossSF =
    math.max(self.crossPB, lineCount > 0 and lines[1].crossMB or 0),
    math.max(self.crossPF, lineCount > 0 and lines[lineCount].crossMF or 0)
  local linePos =
    self.lineFlow == FLEX_FLOW_START and contentCrossSB or
    self.lineFlow == FLEX_FLOW_CENTER and
      (contentCrossSB + cross / 2 - linesThickness / 2 - contentCrossSB) or
    self.lineFlow == FLEX_FLOW_END and (cross - linesThickness - contentCrossSF)
  local crossGap = self.crossPB
  local m1, m2, c1, c2 = inf, -inf, inf, -inf
  for lineNumber, line in pairs(lines) do
    crossGap = math.max(crossGap, line.crossMB)
    if lineNumber > 1 then
      linePos = linePos + crossGap
    end
    local mainPos =
      self.mainFlow == FLEX_FLOW_START and 0 or
      self.mainFlow == FLEX_FLOW_CENTER and line.remainder / 2 or
      self.mainFlow == FLEX_FLOW_END and line.remainder
    local mainGap = self.mainPB
    for i, item in ipairs(line) do
      mainGap = math.max(mainGap, item.mainMB)
      mainPos = mainPos + mainGap
      local crossFlow = item.selfCrossFlow or self.crossFlow
      local crossSize =
        crossFlow == FLEX_FLOW_STRETCH and line.cross or
        item:DesiredCross()
      local crossPos =
        crossFlow == FLEX_FLOW_CENTER and line.cross / 2 - crossSize / 2 or
        crossFlow == FLEX_FLOW_END and
          line.cross - crossSize - math.max(0, item.crossMF - line.crossMF) or
          math.max(0, item.crossMB - crossGap)
      local ms, cs = item.targetMain, crossSize
      local mp, cp = mainPos, linePos + crossPos
      m1 = math.min(m1, mp - math.max(item.mainMB, self.mainPB))
      c1 = math.min(c1, cp - math.max(item.crossMB, self.crossPB))
      m2 = math.max(m2, mp + ms + math.max(item.mainMF, self.mainPF))
      c2 = math.max(c2, cp + cs + math.max(item.crossMF, self.crossPF))
      local ix, iy, iw, ih = ms, cs, mp, cp
      if not isHorizontal then
        ix, iy = iy, ix
        iw, ih = ih, iw
      end
      item:SetSize(ix, iy)
      item:SetPos(iw - self.offsetX, ih - self.offsetY)
      mainPos = mainPos + ms
      item.targetMain = nil
      mainGap = item.mainMF
    end
    linePos = linePos + line.cross
    crossGap = line.crossMF
  end
  local cw, ch = m2 - m1, c2 - c1
  self.overflowXB, self.overflowXF = math.min(m1, 0), -math.min(main - m2, 0)
  self.overflowYB, self.overflowYF = math.min(c1, 0), -math.min(cross - c2, 0)
  if not isHorizontal then
    cw, ch = ch, cw
    self.overflowXB, self.overflowXF, self.overflowYB, self.overflowYF =
      self.overflowYB, self.overflowYF, self.overflowXB, self.overflowXF
  end
  self.cw, self.ch = cw, ch
  self:AutoSize()
  self:UpdateScrollbars()
end

function FLEX:Paint(w, h)
  if self.bgColor then
    surface.SetDrawColor(self.bgColor)
    surface.DrawRect(0, 0, w, h)
  end
end

function FLEX:OnMouseWheeled(delta)
  if input.IsKeyDown(KEY_LSHIFT) then
    if self.scrollX and (self.overflowXB < 0 or self.overflowXF > 0) then
      local newOffset = math.Clamp(self.offsetX - delta * self.scrollSpeedX, self.overflowXB, self.overflowXF)
      if self.offsetX ~= newOffset then
        self.offsetX = newOffset
        self:InvalidateLayout(true)
        return true
      end
    end
  else
    if self.scrollY and (self.overflowYB < 0 or self.overflowYF > 0) then
      local newOffset = math.Clamp(self.offsetY - delta * self.scrollSpeedY, self.overflowYB, self.overflowYF)
      if self.offsetY ~= newOffset then
        self.offsetY = newOffset
        self:InvalidateLayout(true)
        return true
      end
    end
  end
end

local FLEXTEXT = vgui.Register('FlexText', {}, 'Flex')

function FLEXTEXT:Init()
  local label = self:Add('DLabel')
  self.label = label
  label:SetAutoStretchVertical(true)
end

function FLEXTEXT:SetText(text)
  self.label:SetText(text)
end

function FLEXTEXT:PerformLayout(w, h)
  if not self:GetParent().flex then
    self:SetFlowDir(self.dir)
  end
  self.label:SetPos(self.pl, self.pt)
  self.label:SetWide(w - self.pr - self.pl)
  self.label:SetWrap(self.wrap ~= FLEX_WRAP_NONE)
  local tw, th = self.label:GetTextSize()
  self.cw, self.ch = self.pl + tw + self.pr, self.pt + th + self.pb
  self:UpdateScrollbars()
  self:AutoSize()
end

local inspector

local PROPWANG = vgui.RegisterTable({}, 'DNumberWang')

function PROPWANG:SetProp(propData)
  self.propData = propData
  self:SetMinMax(propData.min or 0, propData.max or 10000)
  self:SetDecimals(propData.decimals or 0)
end

function PROPWANG:OnValueChanged(val)
  local target = inspector and inspector.target
  if IsValid(target) then
    if self.propData.setValue then
      self.propData.setValue(target, val)
    else
      target[self.propData.prop] = tonumber(val)
    end
    target:GetParent():InvalidateChildren(true)
  end
end

function PROPWANG:Think()
  local target = inspector and inspector.target
  if IsValid(target) then
    self:SetEnabled(true)
    local paramVal = target[self.propData.prop]
    if self.oldValue ~= paramVal then
      self.oldValue = paramVal
      self:SetValue(paramVal)
    end
  else
    self:SetEnabled(false)
  end
end

local PROPCOMBO = vgui.RegisterTable({}, 'DComboBox')

function PROPCOMBO:SetProp(propData)
  self.propData = propData
  self.optionCache = {}
  for i, option in pairs(propData.options) do
    self.optionCache[option.val] = self:AddChoice(option.text, option.val)
  end
  self.optionCache['UNSET'] = self:AddChoice('unset')
  self:ChooseOptionID(self.optionCache['UNSET'])
end

function PROPCOMBO:Think()
  local target = inspector and inspector.target
  if IsValid(target) then
    self:SetEnabled(true)
    local paramVal = target[self.propData.prop]
    if self.oldValue ~= paramVal then
      self.oldValue = paramVal
      local opt = self.optionCache[paramVal] or self.optionCache['UNSET']
      self:ChooseOptionID(opt)
    end
  else
    self:SetEnabled(false)
  end
end

function PROPCOMBO:OnSelect(id, text, val)
  local target = inspector and inspector.target
  if IsValid(target) then
    if self.propData.setValue then
      self.propData.setValue(target, val)
    else
      target[self.propData.prop] = tonumber(val)
    end
    target:GetParent():InvalidateChildren(true)
  end
end

local PROPBOOL = vgui.RegisterTable({ controlWidth = 16 }, 'DCheckBox')

function PROPBOOL:SetProp(propData)
  self.propData = propData
end

function PROPBOOL:Think()
  local target = inspector and inspector.target
  if IsValid(target) then
    self:SetEnabled(true)
    local paramVal = target[self.propData.prop]
    if self.oldValue ~= paramVal then
      self.oldValue = paramVal
      self:SetChecked(paramVal)
    end
  else
    self:SetEnabled(false)
  end
end

function PROPBOOL:OnChange(val)
  local target = inspector and inspector.target
  if IsValid(target) then
    if self.propData.setValue then
      self.propData.setValue(target, val)
    else
      target[self.propData.prop] = val
    end
    target:GetParent():InvalidateChildren(true)
  end
end

local INSPECTOR = vgui.RegisterTable({}, 'DFrame')

local propGroups = {
  {
    'Size',
    { prop = 'w', control = PROPWANG, label = 'width', desc = 'Width of the panel' },
    { prop = 'wMin', control = PROPWANG, label = 'min-width', desc = 'Minimum width' },
    { prop = 'wMax', control = PROPWANG, label = 'max-width', desc = 'Maximum width' },
    { prop = 'wAuto', control = PROPBOOL, label = 'auto-width',
      desc = 'Automatically set width based on content width' },
    { prop = 'h', control = PROPWANG, label = 'height', 'Height of the panel' },
    { prop = 'hMin', control = PROPWANG, label = 'min-height', desc = 'Minimum height' },
    { prop = 'hMax', control = PROPWANG, label = 'max-height', desc = 'Maximum height' },
    { prop = 'hAuto', control = PROPBOOL, label = 'auto-height',
      desc = 'Automatically set height based on content height' },
  },
  {
    'Spacing',
    { prop = 'ml', control = PROPWANG, label = 'margin-left', setValue = function(target, val)
      local _, t, r, b = target:GetDockMargin()
      target:DockMargin(val, t, r, b)
    end },
    { prop = 'mt', control = PROPWANG, label = 'margin-top', setValue = function(target, val)
      local l, _, r, b = target:GetDockMargin()
      target:DockMargin(l, val, r, b)
    end },
    { prop = 'mr', control = PROPWANG, label = 'margin-right', setValue = function(target, val)
      local l, t, _, b = target:GetDockMargin()
      target:DockMargin(l, t, val, b)
    end },
    { prop = 'mb', control = PROPWANG, label = 'margin-bottom', setValue = function(target, val)
      local l, t, r, _ = target:GetDockMargin()
      target:DockMargin(l, t, r, val)
    end },
    { prop = 'pl', control = PROPWANG, label = 'padding-left', setValue = function(target, val)
      local _, t, r, b = target:GetDockPadding()
      target:DockPadding(val, t, r, b)
    end },
    { prop = 'pt', control = PROPWANG, label = 'padding-top', setValue = function(target, val)
      local l, _, r, b = target:GetDockPadding()
      target:DockPadding(l, val, r, b)
    end },
    { prop = 'pr', control = PROPWANG, label = 'padding-right', setValue = function(target, val)
      local l, t, _, b = target:GetDockPadding()
      target:DockPadding(l, t, val, b)
    end },
    { prop = 'pb', control = PROPWANG, label = 'padding-bottom', setValue = function(target, val)
      local l, t, r, _ = target:GetDockPadding()
      target:DockPadding(l, t, r, val)
    end },
  },
  {
    'Flex parameters',
    { prop = 'dir', control = PROPCOMBO, label = 'direction', options = {
      { text = 'row', val = FLEX_DIR_ROW },
      { text = 'column', val = FLEX_DIR_COL },
    } },
    { prop = 'wrap', control = PROPCOMBO, label = 'wrap', options = {
      { text = 'nowrap', val = FLEX_WRAP_NONE },
      { text = 'before-shrink', val = FLEX_WRAP_BEFORE_SHRINK },
      { text = 'after-shrink', val = FLEX_WRAP_AFTER_SHRINK },
    } },
    { prop = 'mainFlow', control = PROPCOMBO, label = 'main-flow', options = {
      { text = 'start', val = FLEX_FLOW_START },
      { text = 'center', val = FLEX_FLOW_CENTER },
      { text = 'end', val = FLEX_FLOW_END },
    } },
    { prop = 'lineFlow', control = PROPCOMBO, label = 'line-flow', options = {
      { text = 'start', val = FLEX_FLOW_START },
      { text = 'center', val = FLEX_FLOW_CENTER },
      { text = 'end', val = FLEX_FLOW_END },
    } },
    { prop = 'crossFlow', control = PROPCOMBO, label = 'cross-flow', options = {
      { text = 'start', val = FLEX_FLOW_START },
      { text = 'center', val = FLEX_FLOW_CENTER },
      { text = 'end', val = FLEX_FLOW_END },
      { text = 'stretch', val = FLEX_FLOW_STRETCH },
    } },
    { prop = 'selfCrossFlow', control = PROPCOMBO, label = 'self-cross-flow', options = {
      { text = 'start', val = FLEX_FLOW_START },
      { text = 'center', val = FLEX_FLOW_CENTER },
      { text = 'end', val = FLEX_FLOW_END },
      { text = 'stretch', val = FLEX_FLOW_STRETCH },
    } },
    { prop = 'grow', control = PROPWANG, label = 'grow' },
    { prop = 'shrink', control = PROPWANG, label = 'shrink' },
  },
}

local function addPropDesc(root, param, paramName, desc)
  local paramDesc = param:Add('FlexText')
  paramDesc.wrap = FLEX_WRAP_BEFORE_SHRINK
  paramDesc:SetText(desc)
  paramDesc.w = 1000
  paramDesc.hAuto = true
  paramDesc:DockMargin(4, 4, 4, 4)
  paramDesc:DockPadding(4, 4, 4, 4)
  paramDesc.shrink = 1
  paramDesc:Hide()
  paramName.DoClick = function(p)
    if paramDesc.animating then return end
    paramDesc.animating = true
    local expanded = paramDesc:IsVisible()
    paramDesc.hAuto = false
    root:Anim(0.25, FLEX_INTERP_SMOOTH, expanded and function(progress)
    paramDesc.h = (1 - progress) * paramDesc.ch
    end or function(progress)
      if not paramDesc:IsVisible() then
        paramDesc:Show()
        paramDesc:InvalidateLayout(true)
      end
      paramDesc.h = progress * paramDesc.ch
    end, function()
      paramDesc.animating = false
      paramDesc.hAuto = true
      if expanded then paramDesc:Hide() end
    end)
  end
end

function INSPECTOR:Init()
  self:SetTitle('Flex inspector')
  self:SetWide(300)
  self:SetTall(ScrW() / 2)
  self:AlignRight(8)
  self:CenterVertical()
  self:MakePopup()
  self:SetSizable(true)
  local root = self:Add('Flex')
  root:Dock(FILL)
  root.wrap = FLEX_WRAP_BEFORE_SHRINK
  for groupName, props in pairs(propGroups) do
    local group = root:Add('Flex')
    group:DockMargin(8, 8, 8, 8)
    group:DockPadding(8, 8, 8, 8)
    group.wrap = FLEX_WRAP_BEFORE_SHRINK
    group.grow = 1
    group.shrink = 1
    group.w = 200
    group.wMin = 200
    group.hAuto = true
    group.bgColor = Color(0, 0, 0, 64)
    for prop, propData in pairs(props) do
      local param = group:Add('Flex')
      param:DockMargin(4, 4, 4, 4)
      param:DockPadding(4, 4, 4, 4)
      param.bgColor = Color(0, 0, 0, 64)
      param.w = 200
      param.hAuto = true
      param.grow = 1
      param.shrink = 1
      param.wrap = FLEX_WRAP_BEFORE_SHRINK
      param.crossFlow = FLEX_FLOW_STRETCH
      local paramNameContainer = param:Add('Flex')
      paramNameContainer:DockPadding(4, 0, 0, 0)
      paramNameContainer.h = 16
      paramNameContainer.grow = 1
      paramNameContainer.shrink = 1
      local paramName = paramNameContainer:Add('DLabel')
      paramName:Dock(FILL)
      if isstring(propData) then
        param.w = 10000
        paramName:SetContentAlignment(5)
        paramName:SetText(propData)
      else
        paramName:SetText(propData.label)
        paramName:SetContentAlignment(4)
        paramName:SetMouseInputEnabled(true)
        local controlContainer = param:Add('Flex')
        local control = controlContainer:Add(propData.control)
        control:SetProp(propData)
        control:SetWide(propData.control.controlWidth or 100)
        controlContainer.w, controlContainer.h = control:GetSize()
        if propData.desc then
          addPropDesc(root, param, paramName, propData.desc)
        end
      end
      paramName:SizeToContents()
      paramNameContainer.wMin = paramName:GetWide()
    end
  end
end

local lastInspectorToggle = 0

hook.Add('CreateMove', 'flex.inspect', function()
  if input.WasKeyPressed(KEY_C) and
    input.IsKeyDown(KEY_LCONTROL) and
    input.IsKeyDown(KEY_LSHIFT) and
    CurTime() - lastInspectorToggle > 0.1
  then
    lastInspectorToggle = CurTime()
    if IsValid(inspector) then
      inspector:Remove()
    else
      inspector = vgui.CreateFromTable(INSPECTOR)
    end
  end
end)

local function drawHollowRect(x1, y1, w1, h1, x2, y2, w2, h2)
  surface.DrawRect(x1, y1, x2 - x1, h1)
  surface.DrawRect(x2 + w2, y1, w1 - w2 - (x2 - x1), h1)
  surface.DrawRect(x2, y1, w2, y2 - y1)
  surface.DrawRect(x2, y2 + h2, w2, h1 - h2 - (y2 - y1))
end

local marginColor = Color(255, 255, 100, 64)
local paddingColor = Color(100, 255, 100, 64)
local contentColor = Color(200, 200, 255, 32)
local colorGrow = Color(0, 255, 0, 255)
local colorShrink = Color(255, 0, 0, 255)
local colorDbgText = Color(255, 255, 255, 255)
local colorDbgTextBg = Color(0, 0, 0, 255)

local function drawFlexBounds(flex, verbose)
  local x, y = vgui.GetWorldPanel():GetChildPosition(flex)
  local w, h = flex:GetSize()
  local marX, marY = x - flex.mainMB, y - flex.crossMB
  local marW, marH = w + flex.mainMB + flex.mainMF, h + flex.crossMB + flex.crossMF
  local conX, conY = x + flex.mainPB, y + flex.crossPB
  local conW, conH = w - flex.mainPB - flex.mainPF, h - flex.crossPB - flex.crossPF
  surface.SetDrawColor(marginColor)
  drawHollowRect(marX, marY, marW, marH, x, y, w, h)
  surface.SetDrawColor(paddingColor)
  drawHollowRect(x, y, w, h, conX, conY, conW, conH)
  surface.SetDrawColor(contentColor)
  surface.DrawRect(conX, conY, conW, conH)
  if verbose then
    draw.SimpleTextOutlined(
      w,
      'Default',
      x + w / 2,
      y - 8,
      w > flex.w and colorGrow or w < flex.w and colorShrink or colorDbgText,
      TEXT_ALIGN_CENTER,
      TEXT_ALIGN_BOTTOM,
      1,
      colorDbgTextBg
    )
    draw.SimpleTextOutlined(
      h,
      'Default',
      x - 8,
      y + h / 2,
      h > flex.h and colorGrow or h < flex.h and colorShrink or colorDbgText,
      TEXT_ALIGN_RIGHT,
      TEXT_ALIGN_CENTER,
      1,
      colorDbgTextBg
    )
    local cx, cy = flex:GetPos()
    draw.SimpleTextOutlined(
      cx .. ', ' .. cy,
      'Default',
      x - 8,
      y - 8,
      colorDbgText,
      TEXT_ALIGN_RIGHT,
      TEXT_ALIGN_BOTTOM,
      1,
      colorDbgTextBg
    )
  end
end

local function getPanelFlex(pnl)
  while pnl and not pnl.flex do
    pnl = pnl:GetParent()
  end
  return pnl
end

hook.Add('PostRenderVGUI', 'flex.inspect', function()
  if not IsValid(inspector) then return end
  if IsValid(inspector.target) then
    drawFlexBounds(inspector.target, true)
  end
  if input.IsKeyDown(KEY_LSHIFT) then
    local flex = getPanelFlex(vgui.GetHoveredPanel())
    if flex and flex ~= inspector.target then
      drawFlexBounds(flex)
    end
  end
end)

hook.Add('VGUIMousePressed', 'flex.inspect', function(pnl, mcode)
  if not IsValid(inspector) or not input.IsKeyDown(KEY_LSHIFT) then return end
  if mcode == MOUSE_LEFT then
    local flex = getPanelFlex(pnl)
    if flex then
      inspector.target = flex
    end
  else
    inspector.target = nil
  end
end)
