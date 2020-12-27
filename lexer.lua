--lexer made specifically for lua code.

--arbitrarily delimited long strings & comments (e.g. '[==[') are currently not supported

local function lookupify(t)
  local new = {}
  for _, k in ipairs(t) do
    new[k] = true
  end
  return new
end

local keywords = lookupify{
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"
}

local groupPunctuation = lookupify{
  "==", "~=", "<=", ">=", "..", "..."
}

local stringEscapeChars = {
  ["a"] = "\a",
  ["b"] = "\b",
  ["f"] = "\f",
  ["n"] = "\n",
  ["r"] = "\r",
  ["t"] = "\t",
  ["v"] = "\v",
  ["\\"] = "\\",
  ['"'] = '"',
  ["'"] = "'",
  ["["] = "[",
  ["]"] = "]"
}

local lexer = {}
lexer.__index = lexer

function lexer.new(code, filename)
  local obj = setmetatable({}, lexer)
  
  obj.filename = filename or "code"
  
  obj.code = code
  obj.index = 1
  obj:updateCurChar()
  
  obj.currentLine = 1
  
  obj.stopped = false
  
  return obj
end

function lexer:advance(times)
  times = times or 1
  for i=1, times do
    if not self.stopped then
      self.index = self.index + 1
      self:updateCurChar()
      if self.curChar == "\n" then
        self.currentLine = self.currentLine + 1
      end
      if self.index > #self.code then
        self.stopped = true
      end
    end
  end
end

function lexer:updateCurChar()
  self.curChar = self.code:sub(self.index, self.index)
end
function lexer:getNextChar()
  return self.code:sub(self.index+1, self.index+1)
end
function lexer:prevChar()
  return self.code:sub(self.index-1, self.index-1)
end

function lexer:eat(times)
  times = times or 1
  local value = self.code:sub(self.index, self.index + times - 1)
  self:advance(times)
  return value
end

--returns value, type
function lexer:nextToken()
  --skip any spaces, newlines and comments
  while not self.stopped and self.curChar:find("%s") do
    self:advance()
  end
  
  if self.stopped then
    return "", "EOF"
  end
  
  local tokenValue = ""
  local tokenType
  
  local char = self.curChar
  
  if self.code:sub(self.index, self.index + 1) == "--" then
    --comment
    tokenValue = self:eat(2)
    if self.code:sub(self.index, self.index + 1) == "[[" then
      --multiline comment
      tokenValue = tokenValue .. "[["
      self:advance(2)
      while self.code:sub(self.index, self.index + 1) ~= "]]" do
        tokenValue = tokenValue .. self:eat()
        if self.stopped then
          self:syntaxError("unfinished long comment")
        end
      end
      self:advance()
      
      tokenValue = tokenValue .. "]]"
      
      tokenType = "multilineComment"
    else
      --single line comment
      while not self.curChar:find("[\r\n]") and not self.stopped do
        tokenValue = tokenValue .. self:eat()
      end
      
      tokenType = "singleComment"
    end
    
  elseif char:find("[%a_]") then
    --identifier or keyword
    while self.curChar:find("[%w_]") do
      tokenValue = tokenValue .. self.curChar
      self:advance()
    end
    
    tokenType = keywords[tokenValue] and "keyword" or "identifier"
  elseif char:find("%d") then
    --number
    local pattern = "[%d%.]"
    
    if self.curChar == "0" and self:getNextChar() == "x" then
      --hex number
      pattern = "[x%x%.]"
    end
    
    while self.curChar:find(pattern) do
      tokenValue = tokenValue .. self.curChar
      self:advance()
    end
    
    if not tonumber(tokenValue) then
      self:syntaxError("malformed number: '" .. tokenValue .. "'")
    end
    
    tokenType = "number"
    
  elseif char == '"' or char == "'" then
    --string
    local stringEnd = char
    
    self:advance()
    
    while self.curChar ~= stringEnd do
      if self.curChar:find("[\r\n]") then
        --quoted strings must end on the same line (unless escaped)
        self:syntaxError("unfinished string")
      elseif self.curChar == "\\" then
        --backslash escape sequence
        self:advance()
        if self.curChar == "x" then
          --hexadecimal character code (exactly 2 digits)
          local code = ""
          self:advance()
          for i=1, 2 do
            code = code .. self.curChar
            if self.stopped or not self.curChar:find("%x") then
              self:escapeSequenceError("x" .. code)
            end
            self:advance()
          end
          tokenValue = tokenValue .. string.char(tonumber(code, 16))
          
        elseif self.curChar:find("%d") then
          --decimal character code (up to 3 digits)
          local code = ""
          while self.curChar:find("%d") and #code < 3 do
            code = code .. self.curChar
            self:advance()
          end
          if tonumber(code) > 255 then
            self:escapeSequenceError(code)
          end
          tokenValue = tokenValue .. string.char(tonumber(code))
          
        elseif self.curChar == "z" then --in vanilla lua since 5.2, but also in luajit
          --skip any spaces and newlines
          self:advance()
          while self.curChar:find("%s") do
            self:advance()
          end
          
        elseif self.curChar:find("[\r\n]") then
          --insert literal newline
          tokenValue = tokenValue .. "\n"
          
        elseif stringEscapeChars[self.curChar] then
          --escape C-like character
          tokenValue = tokenValue .. stringEscapeChars[self.curChar]
          self:advance()
          
        else
          self:escapeSequenceError(self.curChar)
        end
      else
        tokenValue = tokenValue .. self.curChar
        self:advance()
      end
    end
    
    self:advance()
    
    tokenType = "string"
    
  elseif self.code:sub(self.index, self.index + 1) == "[[" then
    --multiline string
    --NOTE: characters are not escaped here
    self:advance(2)
    if self.curChar:find("[\r\n]") then
      --newline immediately after opening brackets is skipped
      self:advance(self.curChar == "\r" and 2 or 1) --to support both lf and crlf line endings
    end
    while self.code:sub(self.index, self.index + 1) ~= "]]" do
      tokenValue = tokenValue .. self.curChar
      self:advance(1)
      if self.stopped then
        self:syntaxError("unfinished long string")
      end
    end
    self:advance(2)
    
    tokenType = "string"
    
  elseif char:find("%p") then
    --punctuation
    tokenValue = char
    self:advance()
    
    while groupPunctuation[tokenValue .. self.curChar] do
      tokenValue = tokenValue .. self.curChar
      self:advance()
    end
    
    tokenType = "punctuation"
  end
  
  return tokenValue, tokenType
end

function lexer:syntaxError(msg)
  error(("\n%s:%d: %s"):format(self.filename, self.currentLine, msg))
end

function lexer:escapeSequenceError(seq)
  self:syntaxError("invalid escape sequence: '\\" .. seq .. "'")
end

return lexer