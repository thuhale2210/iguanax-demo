function main(Data)
   -- Parse the HL7 message
   local msg, msgType = hl7.parse{vmd='simple.vmd', data=Data}
   
   -- Get facility from MSH-4
   local facility = tostring(msg.MSH[4][1])
   
   -- Determine routing destination
   local destination = route_message(facility)
   
   --  Apply PII masking if going to non-prod
   local outputData = Data
	if destination ~= 'PRODUCTION' then
      if string.find(Data, "PID|") then
         msg = mask_pii(msg)
         outputData = msg:S()
      else
         iguana.logInfo("PII masking: Skipped")
      end
   end
   
   -- Log the decision
   iguana.logInfo("ROUTING: " .. (msgType or "UNKNOWN") .. " from [" .. facility .. "] --> " .. destination)
   
   -- Pass to next component
   queue.push{data=outputData}
end

local ROUTING_TABLE = {
   MAIN_HOSPITAL = "PRODUCTION",
   LAB           = "PRODUCTION",
   RADIOLOGY     = "PRODUCTION",
   PHARMACY      = "PRODUCTION",
   EMERGENCY     = "PRODUCTION",
   CLINIC        = "PRODUCTION",
   ICU           = "PRODUCTION",
   SURGERY       = "PRODUCTION",
   TEST_CLINIC   = "NON-PRODUCTION",
   DEV_SYSTEM    = "NON-PRODUCTION",
   UAT_ENV       = "NON-PRODUCTION",
   TRAINING_LAB  = "NON-PRODUCTION",
   SANDBOX       = "NON-PRODUCTION"
}

function route_message(facility)
   local f = string.upper(facility)
   return ROUTING_TABLE[f] or "NON-PRODUCTION (default)"
end

function mask_pii(msg)
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