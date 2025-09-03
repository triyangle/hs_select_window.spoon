---
--- dmg hammerspoon
---

local obj={}
obj.__index = obj

-- metadata

obj.name = "selectWindow"
obj.version = "0.3"
obj.author = "dmg <dmg@turingmachine.org>"
obj.homepage = "https://github.com/dmgerman/hs_select_window.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"


-- things to configure

obj.rowsToDisplay = 14 -- how many rows to display in the chooser


-- do we show the current selected window on the right corner of the screen?
obj.showCurrentlySelectedWindow = nil

-- whether to use fuzzy searching for the chooser (default: false)
obj.useFuzzySearch = false

-- delay for the timer... it only refreshes at this interval
obj.displayDelay = 0.2


-- keep track of hotkeys so we can disable/enable them
obj.hotkeys = {}
obj.modalKeys = hs.hotkey.modal.new()

obj.modalKeys:bind({}, "tab", function()
    -- toggle it when typing tab
    obj.showCurrentlySelectedWindow = not obj.showCurrentlySelectedWindow
end)


-- 
obj.trackChooser = nil    -- timer callback to track the chooser selection
obj.trackPrevWindow = nil -- previous window shown in the chooser, so we don't update
                          -- unnecessarily
obj.imageCache = {}       -- cache images created... since it is the slowest part
obj.pendingCaptures = {}  -- track pending async captures by window id
obj.overlay = nil         -- keep track of the snapshop being displayed
obj.overlayHeightRatio = 0.4 -- ratio of the screen to use for the overlay




-- for debugging purposes
function obj:print_table(t, f)
--   for i,v in ipairs(t) do
--      print(i, f(v))
--   end
end


-- lightweight fuzzy matching function
-- returns a numeric score (higher is better) or nil if no match
local function fuzzy_score(haystack, needle)
  if not needle or needle == "" then return 1 end
  local s = string.lower(haystack or "")
  local q = string.lower(needle or "")
  local pos = 1
  local first_pos, last_pos
  for i = 1, #q do
    local c = q:sub(i,i)
    local found = s:find(c, pos, true)
    if not found then
      return nil
    end
    if not first_pos then first_pos = found end
    last_pos = found
    pos = found + 1
  end
  -- score favors more matched characters and more compact matches
  local matched = #q
  local spread = (last_pos or 0) - (first_pos or 0) + 1
  local score = matched * 100 - spread
  return score
end

function obj:hotkeys_enable(enable)
  for _,v in pairs (obj.hotkeys)do
    if enable then
      v:enable()
    else
      v:disable()
    end
  end
end

-- for debugging purposes

function obj:print_windows()
  function w_info(w)
     return string.format("[%s] [%s] [%s]",
       w:application():bundleID(),
       w:application():name(),
       w:title()
     )
   end
   obj:print_table(hs.window.visibleWindows(), w_info)
end

theWindows = hs.window.filter.new()
theWindows:setDefaultFilter{}
theWindows:setSortOrder(hs.window.filter.sortByFocusedLast)
obj.currentWindows = {}
obj.previousSelection = nil  -- the idea is that one switches back and forth between two windows all the time


-- Start by saving all windows

for i,v in ipairs(theWindows:getWindows()) do
   table.insert(obj.currentWindows, v)
end

function obj:find_window_by_title(t)
   -- find a window by title.
   for i,v in ipairs(obj.currentWindows) do
      if string.find(v:title(), t) then
         return v
      end
   end
   return nil
end

function obj:focus_by_title(t)
   -- focus the window with given title
   if not t then
      hs.alert.show("No string provided to focus_by_title")
      return nil
   end
   w = obj:find_window_by_title(t)
   if w then
      w:focus()
   end
   return w
end

function obj:focus_by_app(appName)
   -- find a window with that application name and jump to it
--   print(' [' .. appName ..']')
   for i,v in ipairs(obj.currentWindows) do
--      print('           [' .. v:application():name() .. ']')
      if string.find(v:application():name(), appName) then
--         print("Focusing window" .. v:title())
         v:focus()
         return v
      end
   end
   return nil
end

function obj:focus_by_bundle_id(bundleID)
  -- find a window with that application name and jump to it
  --   print(' [' .. appName ..']')
  for i,v in ipairs(obj.currentWindows) do
    --      print('           [' .. v:application():name() .. ']')
    if string.find(v:application():bundleID(), bundleID) then
      --         print("Focusing window" .. v:title())
      v:focus()
      return v
    end
  end
  return nil
end


function obj:focus_by_app_and_title(appName, title)
  -- find a window with that application name and jump to it
  --   print(' [' .. appName ..']')
  for i,v in ipairs(obj.currentWindows) do
--     print('           [' .. v:application():name() .. ']')
    if (v:application():name() == appName) and string.find(v:title(), title) then
      --         print("Focusing window" .. v:title())
      v:focus()
      return v
    end
  end
  return nil
end


-- the hammerspoon tracking of windows seems to be broken
-- we do it ourselves

local function callback_window_created(w, appName, event)

   if event == "windowDestroyed" then
--      print("deleting from windows-----------------", w)
--      if w then
--         print("destroying window" .. w:title())
--      end
      for i,v in ipairs(obj.currentWindows) do
         if v == w then
            table.remove(obj.currentWindows, i)
            return
         end
      end
--      print("Not found .................. ", w)
--      obj:print_table0(obj.currentWindows)
--      print("Not found ............ :()", w)
      return
   end
   
   if event == "windowCreated" then
--      if w then
--         print("creating window" .. w:title())
--      end
--      print("inserting into windows.........", w)
      table.insert(obj.currentWindows, 1, w)
      return
   end
   if event == "windowFocused" then
      --otherwise is equivalent to delete and then create
--      if w then
--         print("Focusing window" .. w:title())
--      end
      callback_window_created(w, appName, "windowDestroyed")
      callback_window_created(w, appName, "windowCreated")
--      obj:print_table0(obj.currentWindows)
   end
end
theWindows:subscribe(hs.window.filter.windowCreated, callback_window_created)
theWindows:subscribe(hs.window.filter.windowDestroyed, callback_window_created)
theWindows:subscribe(hs.window.filter.windowFocused, callback_window_created)


function obj:count_app_windows(currentApp)
   local count = 0
   for i,w in ipairs(obj.currentWindows) do
      local app = w:application()
      if  (app == currentApp) then
          count = count + 1
      end
   end
   return count
end


function obj:list_window_choices(onlyCurrentApp, currentWin)
   local windowChoices = {}
   local currentApp = currentWin:application()
--  print("\nstarting to populate")
--   print(currentApp)
   for i,w in ipairs(obj.currentWindows) do
      if w ~= currentWin then
         local app = w:application()
         local appName  = '(none)'
         if app then
           appName = app:name()
           -- add bundle id, to separate windows with same name, but different
           -- bundleID
            appBundleId = app:bundleID()
               end
         if (not onlyCurrentApp) or (app == currentApp) then
--            print("inserting...")
           local windowImage= nil
           local appImage = hs.image.imageFromAppBundle(w:application():bundleID())
            table.insert(windowChoices, {
                            text = w:title() .. "--" .. appName,
                            subText = appBundleId,
                            uuid = i,
                            image = appImage,
                            wImage = nil, -- populated by display_currently_selected_window_callback
                            win=w})
         end
      end
   end
   return windowChoices;
end



function obj:windowActivate(w)
  if w then
    w:focus()
    -- this fixes a bug when the application is a different screen 
    w:application():activate()
  else
    hs.alert.show("unable fo focus " .. name)
  end

end  

function obj:selectWindowGeneric(fnListWindows)
   local windowChooser = hs.chooser.new(function(choice)
       obj:leave_chooser()

       if not choice then
         return
       end
       local v = choice["win"]
       if v then
--         hs.alert.show("doing something, we have a v")
--         print(v)
         if moveToCurrentSpace then
           hs.alert.show("move to current")
           -- we don't want to keep the window maximized
           -- move to the current space... so we leave that space alone
           if v:isFullScreen() then
             v:toggleFullScreen()
           end
           hs.spaces.moveWindowToSpace(v,
                hs.spaces.activeSpaceOnScreen(hs.screen.mainScreen())
           )
           v:moveToScreen(mainScreen)
         end
         v:focus()
         v:application():activate()
       else
         hs.alert.show("unable fo focus " .. name)
       end
   end)

   if #obj.currentWindows == 0 then
      hs.alert.show("no other window available ")
      return
   end
   -- show it, so we start catching keyboard events
   obj:enter_chooser(windowChooser)


   -- then fill fill it and let it do its thing
   local windowChoices = fnListWindows()
   if #windowChoices == 0 then
     hs.alert.show("There are no other windows to select.")
     windowChooser:hide()
     return
   end
   if #windowChoices == 1 then
     local v = windowChoices[1]["win"]
     print("activating 2:", hs.inspect(windowChoices))
     print("activating  :", hs.inspect(v))
     windowChooser:hide()
     v:focus()
     v:application():activate()
     return
   end

   -- if fuzzy searching is enabled, override the queryChanged handler
   if obj.useFuzzySearch then
     -- keep a copy of original choices and provide a queryChanged handler
     local originalChoices = windowChoices
     windowChooser:choices(originalChoices)
     windowChooser:rows(obj.rowsToDisplay)
     windowChooser:query(nil)
    windowChooser:queryChangedCallback(function(query)
      if not query or query == "" then
        windowChooser:choices(originalChoices)
        return
      end
      local hits = {}
      for _,choice in ipairs(originalChoices) do
        -- score against text and subText (title + app)
        local score1 = fuzzy_score(choice.text or "", query)
        local score2 = fuzzy_score(choice.subText or "", query)
        local score = nil
        if score1 and score2 then score = math.max(score1, score2)
        elseif score1 then score = score1
        elseif score2 then score = score2 end
        if score then
          table.insert(hits, {score=score, choice=choice})
        end
      end
      table.sort(hits, function(a,b) return a.score > b.score end)
      local sorted = {}
      for i,v in ipairs(hits) do table.insert(sorted, v.choice) end
      if #sorted == 0 then
        -- make sure chooser shows nothing if no matches
        windowChooser:choices({})
      else
        windowChooser:choices(sorted)
      end
    end)
   else
     windowChooser:choices(windowChoices)
     windowChooser:rows(obj.rowsToDisplay)
     windowChooser:query(nil)
   end
end

function obj:selectWindow(onlyCurrentApp, moveToCurrentSpace)
  -- check if we have other windows
  local currentWin = hs.window.focusedWindow()

  if onlyCurrentApp then
    local nWindows = obj:count_app_windows(currentWin:application())
    if nWindows <= 1 then
      hs.alert.show("no other window for this application ")
      return
    end
  end

  obj:selectWindowGeneric(
    function () return obj:list_window_choices(onlyCurrentApp, currentWin) end
  )
end

function obj:selectFirstAppWindow()
  local currentWin = hs.window.focusedWindow()
  local currentApp = currentWin:application()
  local currentBundleID = currentApp:bundleID() or currentApp:name()

  function list_window_first_choices()
    local windowChoices = {}
    local seen = {}
    for i,w in ipairs(obj.currentWindows) do
      local app = w:application()
      local appName = (app and app:name()) or '(none)'
      local bundleID = (app and app:bundleID()) or appnName
      local appImage = nil
      if bundleID and  bundleID ~= currentBundleID and (not seen[bundleID]) then
        seen[bundleID] = w

        if (not onlyCurrentApp) or (app == currentApp) then
          --            print("inserting...")
          if app then
            -- add bundle id, to separate windows with same name, but different
            -- bundleID
            appImage = hs.image.imageFromAppBundle(bundleID)
          end
          table.insert(windowChoices, {
              text = w:title() .. "--" .. appName,
              subText = bundleID,
              uuid = i,
              image = appImage,
              wImage = nil,
              win=w})
        end
      end
    end
    return windowChoices
  end

  obj:selectWindowGeneric(list_window_first_choices)
end



function obj:selectApp(moveToCurrentSpace)
   -- show only first window of a given application

   local currentWin = hs.window.focusedWindow()

   local windowChooser = hs.chooser.new(function(choice)
       obj:leave_chooser()
       if not choice then
         hs.alert.show("Nothing to focus");
         return
       end
       local v = choice["win"]
       if v then
--         hs.alert.show("doing something, we have a v")
--         print(v)
         if moveToCurrentSpace then
           hs.alert.show("move to current")
           -- we don't want to keep the window maximized
           -- move to the current space... so we leave that space alone
           if v:isFullScreen() then
             v:toggleFullScreen()
           end
           hs.spaces.moveWindowToSpace(v,
                hs.spaces.activeSpaceOnScreen(hs.screen.mainScreen())
           )
           v:moveToScreen(mainScreen)
         end
         v:focus()
         v:application():activate()
       else
         hs.alert.show("unable fo focus " .. name)
       end
   end)

   -- check if we have other windows
   if onlyCurrentApp then
      local nWindows = obj:count_app_windows(currentWin:application())
      if nWindows == 0 then
         hs.alert.show("no other window for this application ")
         return
      end
   end
   if #obj.currentWindows == 0 then
      hs.alert.show("no other window available ")
      return
   end

   obj:enter_chooser(windowChooser)
   
   local windowChoices = obj:list_window_choices(onlyCurrentApp, currentWin)
   if obj.useFuzzySearch then
     local originalChoices = windowChoices
     windowChooser:choices(originalChoices)
     windowChooser:rows(obj.rowsToDisplay)
     windowChooser:query(nil)
     windowChooser:queryChangedCallback(function(query)
       if not query or query == "" then
         windowChooser:choices(originalChoices)
         return
       end
       local hits = {}
       for _,choice in ipairs(originalChoices) do
         local score1 = fuzzy_score(choice.text or "", query)
         local score2 = fuzzy_score(choice.subText or "", query)
         local score = nil
         if score1 and score2 then score = math.max(score1, score2)
         elseif score1 then score = score1
         elseif score2 then score = score2 end
         if score then table.insert(hits, {score=score, choice=choice}) end
       end
       table.sort(hits, function(a,b) return a.score > b.score end)
       local sorted = {}
       for i,v in ipairs(hits) do table.insert(sorted, v.choice) end
       if #sorted == 0 then
         windowChooser:choices({})
       else
         windowChooser:choices(sorted)
       end
     end)
   else
     windowChooser:choices(windowChoices)
     windowChooser:rows(obj.rowsToDisplay)
     windowChooser:query(nil)
   end
end

function obj:enter_chooser(windowChooser)
  -- show the chooser 
  -- and enable/disable whatever is necessary when in the
  -- chooser

--  theWindows:pause()
  obj:hotkeys_enable(false)
  obj.pollChooser:start()

  obj.trackPrevWindow = nil
  obj.trackChooser = windowChooser
  obj.imageCache = {}

  windowChooser:show()

  obj.modalKeys:enter()


end

function obj:leave_chooser(chooser)
  -- exiting the chooser
  -- and enable/disable whatever is necessary when 
  -- the chooser returns
  obj:showImageOverlay()
  obj.trackChooser =nil
  obj.trackPrevWindow = nil
  if obj.overlay then
    obj.overlay:delete()
    obj.overlay = nil
  end
  -- TODO we need to delete all the images in the cache
  obj.imageCache = {}

  obj.modalKeys:exit()

--  theWindows:resume()

  obj:hotkeys_enable(true)

end


function obj:previousWindow()
   return obj.currentWindows[2]
end

-- simple function to be able to go back to the previous window
function obj:choosePreviousWindow()
  if obj.currentWindows[2] then
    obj.currentWindows[2]:focus()
  end
end

function obj:nextFullScreen()
  -- find a window by title.
  for i,v in ipairs(obj.currentWindows) do
    if v:isFullScreen() then
      if (obj.currentWindows[1] == v) then
         --        print("it is the currentn window")
         -- do nothing
      else
        v:focus()
        return
      end
    end
  end
  hs.alert("No next fullscreen window")
end

function obj:captureWindowSnapshot(window)
  -- Get the window's ID
  if not window then
    return nil
  end
  local windowID = window:id()

  -- Define the output path for the screenshot
  local outputPath = "/tmp/window_snapshot_" .. windowID .. ".png"

  -- Use screencapture with the window ID to capture the window
  -- fallback synchronous capture (kept for compatibility) - prefer async via requestWindowSnapshot
  local command = "screencapture -x -l" .. windowID .. " " .. outputPath
  hs.execute(command)
  local image = hs.image.imageFromPath(outputPath)
  return image
end


function obj:requestWindowSnapshot(window)
  -- Non-blocking snapshot request. If we already have a cached image, return immediately.
  if not window then return end
  local wid = window:id()
  if not wid then return end
  if obj.imageCache[wid] then return end
  if obj.pendingCaptures[wid] then return end

  obj.pendingCaptures[wid] = true
  local outputPath = "/tmp/window_snapshot_" .. wid .. ".png"

  -- use hs.task to run screencapture asynchronously
  local args = {"-x", "-l" .. tostring(wid), outputPath}
  local task = hs.task.new("/usr/sbin/screencapture", function(exitCode, stdOut, stdErr)
    -- clear pending flag
    obj.pendingCaptures[wid] = nil
    -- load image if created
    local image = hs.image.imageFromPath(outputPath)
    if image then
      obj.imageCache[wid] = image
      -- if chooser is visible and selection still matches this window, show overlay
      if obj.trackChooser and obj.trackChooser:isVisible() then
        local sel = obj.trackChooser:selectedRowContents()
        if sel and sel["win"] and sel["win"]:id() == wid then
          obj:showImageOverlay(image)
          obj.PrevWindow = wid
        end
      end
    end
  end, args)
  -- start the task and detach
  task:start()
end


function obj:showImageOverlay(image)
  -- show the image overlay in the bottom right of the screen
  if obj.overlay then
    obj.overlay:delete()
    obj.overlay = nil
  end
  if not image then
    return
  end
  -- Get screen dimensions (main screen in this case)
  local screenFrame = hs.screen.mainScreen():frame()

  -- if necessary, resize image to fit a reasonable overlay area 
  local origSize = image:size()
  local h = screenFrame.h * obj.overlayHeightRatio
  local newSize = nil
  if h < origSize.h then
    local scale = h / origSize.h
    newSize = hs.geometry.size(origSize.w * scale, h)
  else
    newSize = origSize
  end

  -- Position the overlay in the bottom-right corner (adjust as needed)
  local posX = screenFrame.x + screenFrame.w - newSize.w - 20
  local posY = screenFrame.y + screenFrame.h - newSize.h - 40

  -- Create the drawing
  obj.overlay = hs.drawing.image(hs.geometry.rect(posX, posY, newSize.w, newSize.h), image)

  -- Customize appearance
  obj.overlay:setLevel(hs.drawing.windowLevels.overlay)
  obj.overlay:setAlpha(0.9)
  obj.overlay:show()
end

-- call back to display the snapshot of the currently
-- active window
function display_currently_selected_window_callback()
  
  if obj.trackChooser and obj.trackChooser:isVisible() then
    
    if not obj.showCurrentlySelectedWindow then
      -- user might have disabled it
      obj:showImageOverlay() -- clean any window that is currently being shown
      return
    end

    local selectedWin = obj.trackChooser:selectedRowContents()["win"]
    if selectedWin then
      local wid = selectedWin:id()
      if wid ~= obj.PrevWindow then
        -- if we already have a cached image, show it right away
        local wImage = obj.imageCache[wid]
        if wImage then
          obj:showImageOverlay(wImage)
          obj.PrevWindow = wid
        else
          -- request an async capture; overlay will be shown when capture completes
          obj:requestWindowSnapshot(selectedWin)
        end
      end
    end
  end
end

-- only enable showing the thumbnails when desired
-- it could be a bit slow and will take some memory
obj.pollChooser = hs.timer.doEvery(obj.displayDelay,display_currently_selected_window_callback)
obj.pollChooser:stop()

function obj:bindHotkeys(mapping)
  local def = {
    all_windows                   = function() self:selectWindow(false,false) end,
    all_windows_move_to_current_workspace = function() self:selectWindow(false,true) end,
    app_windows                   = function() self:selectWindow(true, false) end,
    first_window_per_app          = function() self:selectFirstAppWindow() end
  }
  -- do it by hand, so we can keep track of the hotkeys
  for i,v in pairs (mapping)do
    obj.hotkeys[i] = hs.hotkey.bind(v[1], v[2], def[i])
    obj.modalKeys:bind(v[1], v[2], function()
        hs.eventtap.keyStroke({"ctrl"}, "n")
    end)
-- I am just going to assume that nobody is going to use shift to call the function
    local ks = v[1]
    ks[#ks+1] = "shift"
    obj.modalKeys:bind(ks, v[2], function()
        hs.eventtap.keyStroke({"ctrl"}, "p")
    end)
  end

end



return obj

