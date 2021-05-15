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

function lexer:advanceTo(index)
  for _ in self.code:sub(self.index, index):gmatch("\n") do
    self.currentLine = self.currentLine + 1
  end
  self.index = index
  self:updateCurChar()
  if self.index > #self.code then
    self.stopped = true
  end
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
    if self.code:sub(self.index + 2, self.index + 3) == "[[" then
      --multiline comment
      
      local endIndex = self.code:find("]]", self.index + 4)
      if not endIndex then
        self:syntaxError("unfinished multiline comment")
      end
      
      tokenValue = self.code:sub(self.index, endIndex + 1)
      
      tokenType = "multilineComment"
      
      self:advanceTo(endIndex + 2)
    else
      local endIndex = self.code:find("\n", self.index + 2) or #self.code
      tokenValue = self.code:sub(self.index, endIndex - 1)
      
      tokenType = "singleComment"
      self:advanceTo(endIndex)
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
    
    local endIndex = self.code:find("[^\\]" .. stringEnd, self.index + 1)
    if not endIndex then
      self:syntaxError("unfinished string")
    end
    
    tokenValue = self.code:sub(self.index, endIndex + 1)
    
    tokenType = "string"
    
    self:advanceTo(endIndex + 2)
    
  elseif self.code:sub(self.index, self.index + 1) == "[[" then
    --multiline string
    local endIndex = self.code:find("]]", self.index + 2)
    if not endIndex then
      self:syntaxError("unfinished string")
    end
    
    tokenValue = self.code:sub(self.index, endIndex + 1)
    
    tokenType = "string"
    
    self:advanceTo(endIndex + 2)
    
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