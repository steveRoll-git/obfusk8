# obfusk8
A tool for obfuscating Lua code.

Made mainly for the LuaJIT version that the löve engine uses (2.0) but can probably be used with other versions as well.

# Usage
Require it with `require`:
```lua
local obfusk8 = require "obfusk8"
```
To obfuscate Lua code, call `obfusk8` with the code as a string in the first argument.
The obfuscated code will be returned as a string.
```lua
local obfuscatedCode = obfusk8(originalCodeString)
```
You can optionally give an options table as the second argument. The following options are supported:
* `fileName`: string. If given, this will be used when giving error messages. Otherwise the name will just be "`code`".
* `obfuscateLocals`: boolean. Default: `true`. Whether or not to obfuscate the names of local variables.
* `obfuscateTableAccess`: boolean. Default: `true`. Whether or not to obfuscate the names of identifiers when accessing tables.
* `preserveComments`: boolean. Default: `false`. Whether or not to keep the comments from the original source in the resulting code.
* `minimalWhitespace`: boolean. Default: `false`. If `false`, the whitespace (including newlines) in the resulting code will be the same as it was in the original.
If `true`, the generated code will have only minimal whitespace which is needed for the code to be valid. (The code will still be functionally the same)
* `knownGlobals`: table. Default: `nil`. A table where the key is a string, and the value is anything.
Any string keys present will be considered as known global variables, and their names will not be obfuscated.
* `defaultLuaGlobals`: boolean. Default: `true`. Whether or not to add default Lua global variables (as of luajit 2.0) as known globals. If false, the only known globals will be the ones you supplied in the `knownGlobals` table.


# Details
Any names of local variables will be replaced by random names.

Strings that are used as identifiers when accessing tables (e.g. `yourTable.someKey`) are obfuscated to random names.

String constants (quoted and in multiline strings) will be preserved.

Known global variables, and table accesses to them (and any additional accesses from there) will not be obfuscated.