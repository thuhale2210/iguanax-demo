local ROUTING_TABLE = {
   MAIN_HOSPITAL = "PROD",
   LAB = "PROD",
   RADIOLOGY = "PROD",
   PHARMACY = "PROD",
   EMERGENCY = "PROD",
   CLINIC = "PROD",
   ICU = "PROD",
   SURGERY = "PROD",

   TEST_CLINIC = "NONPROD",
   DEV_SYSTEM = "NONPROD",
   UAT_ENV = "NONPROD",
   TRAINING_LAB = "NONPROD",
   SANDBOX = "NONPROD"
}

function RouteFacility(Facility)
   local f = string.upper(Facility or "")
   return ROUTING_TABLE[f] or "NONPROD"
end

function PIImask(msg)
   if not msg.PID then
      return msg
   end
   
   -- Mask patient name
   if msg.PID[5] and msg.PID[5][1] then
      if msg.PID[5][1][1] then
         msg.PID[5][1][1][1] = 'XXXX' -- Family name
      end
      if msg.PID[5][1][2] then
         msg.PID[5][1][2] = 'XXXX' -- Given name          
      end
   end
      
   -- Mask DOB
   if msg.PID[7] then
      msg.PID[7] = 'XXXXXXXX'
   end
            
   -- Mask SIN
   if msg.PID[19] then
      msg.PID[19] = 'XXX-XXX-XXX'
   end
      
   -- Mask phone number
   if msg.PID[13] and msg.PID[13][1] then
      msg.PID[13][1][1] = 'XXX-XXX-XXXX'
   end
      
   -- Mask address
   if msg.PID[11] and msg.PID[11][1] and msg.PID[11][1][1] then
      msg.PID[11][1][1][1] = '123'
      msg.PID[11][1][1][2] = 'MASKED STREET'
   end
      
   if msg.PID[11] and msg.PID[11][1] then
      msg.PID[11][1][3] = 'MASKED CITY'
      msg.PID[11][1][4] = 'MASKED STATE'
      msg.PID[11][1][5] = 'XXXXX'
   end
      
   return msg
end

function validBasicChecks(Data)
   if type(Data) ~= 'string' or #Data < 8 then
      return false, "Message is empty/too short"
   end

   if Data:sub(1,3) ~= "MSH" then
      return false, "Message does not start with MSH"
   end

   local fs = Data:sub(4,4)
   if fs == "\r" or fs == "\n" or fs == "" then
      return false, "Invalid field separator in MSH-1"
   end

   if not Data:find("\r", 1, true) then
      return false, "No segment delimiters (CR). Not a valid HL7 payload"
   end

   -- cheap parse of MSH line for required fields
   local eol = Data:find("\r", 1, true)
   local msh = Data:sub(1, eol-1)
   local f = msh:split(fs)

   -- MSH|... => f[1]="MSH", f[2]=encoding, f[9]=MSH-9, f[10]=MSH-10
   local msgType = f[9] or ""
   local ctrlId  = f[10] or ""

   if msgType == "" then
      return false, "Missing MSH-9 (message type)"
   end
   if ctrlId == "" then
      return false, "Missing MSH-10 (control ID)"
   end

   return true, "OK"
end

function ERRformat(Reason, Data)
   local preview = Data or ""
   if #preview > 2000 then
      preview = preview:sub(1,2000) .. "\n...[truncated]..."
   end

   local out = {}
   out[#out+1] = "HL7 ROUTER ERROR:"
   out[#out+1] = "Time: " .. os.date("!%Y-%m-%dT%H:%M:%SZ")
   out[#out+1] = "Reason: " .. tostring(Reason)
   out[#out+1] = "---- Original Message ----"
   out[#out+1] = preview
   out[#out+1] = ""
   return table.concat(out, "\n")
end

function main(Data)
   local comps = iguana.components()
   local prodId = comps["Test Listener (Prod)"]
   local nonProdId = comps["Test Listener (Nonprod)"]
   local errId = comps["Error Logger (To File)"]

   if not prodId or not nonProdId or not errId then
      error("Missing component IDs. Check names in iguana.components().")
   end

   -- 1) Validate basics
   local ok, reason = validBasicChecks(Data)
   if not ok then
      iguana.logWarning("INVALID HL7 (basic): " .. reason)
      message.send{data=ERRformat(reason, Data), id=errId}
      return
   end

   -- 2) Parse (catches deeper structural issues)
   local msg
   local okParse, errParse = pcall(function()
      msg = hl7.parse{vmd='simple.vmd', data=Data}
   end)

   if not okParse or not msg then
      local r = "HL7 parse failed: " .. tostring(errParse)
      iguana.logWarning(r)
      message.send{data=ERRformat(r, Data), id=errId}
      return
   end

   -- 3) Route
   local facility = tostring(msg.MSH[4][1] or "")
   local route = RouteFacility(facility)

   local out = Data
   if route == "NONPROD" and Data:find("PID|", 1, true) then
      msg = PIImask(msg)
      out = msg:S()
   end

   iguana.logInfo("ROUTER: FACILITY="..facility.." ROUTE="..route)

   if route == "PROD" then
      message.send{data=out, id=prodId}
   else
      message.send{data=out, id=nonProdId}
   end
end