--[[
	Python Terminal IDE para Roblox (LocalScript)
	Simula una terminal Linux donde escribir y ejecutar código Python.
	Colocar en StarterGui o StarterPlayerScripts.
]]

local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- ==============================================
-- RUNTIME PYTHON (tipos, operaciones, builtins)
-- ==============================================
local Py = {}

-- Tipos básicos
local py_none = {type="none"}
local py_true = {type="bool", value=true}
local py_false = {type="bool", value=false}
local function py_int(v) return {type="int", value=v or 0} end
local function py_float(v) return {type="float", value=v or 0.0} end
local function py_str(v) return {type="str", value=tostring(v)} end
local function py_list(t) return {type="list", value=t or {}} end
local function py_dict(d) return {type="dict", value=d or {}} end
local function py_func(f, name) return {type="function", value=f, name=name} end
local function py_bool(b) return b and py_true or py_false end

-- Representación
function Py.repr(val)
	if val == nil or val.type == "none" then return "None"
	elseif val.type == "bool" then return val.value and "True" or "False"
	elseif val.type == "int" then return tostring(val.value)
	elseif val.type == "float" then return string.format("%.6g", val.value)
	elseif val.type == "str" then return '"'..val.value..'"'
	elseif val.type == "list" then
		local parts = {}
		for _,v in ipairs(val.value) do table.insert(parts, Py.repr(v)) end
		return "["..table.concat(parts, ", ").."]"
	elseif val.type == "dict" then
		local parts = {}
		for k,v in pairs(val.value) do
			local key = type(k)=="number" and Py.repr(py_int(k)) or Py.repr(py_str(k))
			table.insert(parts, key..": "..Py.repr(v))
		end
		return "{"..table.concat(parts, ", ").."}"
	elseif val.type == "function" then return "<function "..(val.name or "lambda")..">"
	else return tostring(val)
	end
end

function Py.is_truthy(val)
	if not val or val.type=="none" then return false end
	if val.type=="bool" then return val.value end
	if val.type=="int" then return val.value ~= 0 end
	if val.type=="float" then return val.value ~= 0.0 end
	if val.type=="str" then return val.value ~= "" end
	if val.type=="list" then return #val.value > 0 end
	if val.type=="dict" then return next(val.value) ~= nil end
	return true
end

-- Operadores aritméticos
local function numeric_op(a,b, opfn, opname)
	local ta, tb = a.type, b.type
	if (ta=="int" or ta=="float") and (tb=="int" or tb=="float") then
		local na = (ta=="int") and a.value or a.value
		local nb = (tb=="int") and b.value or b.value
		local res = opfn(na,nb)
		if ta=="int" and tb=="int" and opname~="truediv" then
			return py_int(math.floor(res))
		else
			return py_float(res)
		end
	elseif ta=="str" and tb=="str" and opname=="add" then
		return py_str(a.value .. b.value)
	elseif ta=="list" and tb=="list" and opname=="add" then
		local new = {}
		for _,v in ipairs(a.value) do table.insert(new, v) end
		for _,v in ipairs(b.value) do table.insert(new, v) end
		return py_list(new)
	elseif ta=="str" and tb=="int" and opname=="mul" then
		return py_str(a.value:rep(b.value))
	elseif ta=="int" and tb=="str" and opname=="mul" then
		return py_str(b.value:rep(a.value))
	end
	error("TypeError: unsupported operand type(s) for "..opname..": "..ta.." and "..tb)
end

function Py.add(a,b) return numeric_op(a,b, function(x,y) return x+y end, "add") end
function Py.sub(a,b) return numeric_op(a,b, function(x,y) return x-y end, "sub") end
function Py.mul(a,b) return numeric_op(a,b, function(x,y) return x*y end, "mul") end
function Py.truediv(a,b)
	if (a.type=="int" or a.type=="float") and (b.type=="int" or b.type=="float") then
		local na = (a.type=="int") and a.value or a.value
		local nb = (b.type=="int") and b.value or b.value
		if nb == 0 then error("ZeroDivisionError: division by zero") end
		return py_float(na / nb)
	end
	error("TypeError: unsupported operand type(s) for /")
end
function Py.floordiv(a,b)
	if (a.type=="int" or a.type=="float") and (b.type=="int" or b.type=="float") then
		local na = (a.type=="int") and a.value or a.value
		local nb = (b.type=="int") and b.value or b.value
		if nb == 0 then error("ZeroDivisionError: division by zero") end
		return py_int(math.floor(na / nb))
	end
	error("TypeError: unsupported operand type(s) for //")
end
function Py.mod(a,b)
	if (a.type=="int" or a.type=="float") and (b.type=="int" or b.type=="float") then
		local na = (a.type=="int") and a.value or a.value
		local nb = (b.type=="int") and b.value or b.value
		if nb == 0 then error("ZeroDivisionError: modulo by zero") end
		return py_float(na % nb)
	end
	error("TypeError: unsupported operand type(s) for %")
end
function Py.pow(a,b)
	if (a.type=="int" or a.type=="float") and (b.type=="int" or b.type=="float") then
		return py_float(math.pow(a.value, b.value))
	end
	error("TypeError: unsupported operand type(s) for **")
end

-- Comparaciones
function Py.eq(a,b)
	if a.type=="none" and b.type=="none" then return py_true end
	if a.type=="bool" and b.type=="bool" then return py_bool(a.value==b.value) end
	if (a.type=="int" or a.type=="float") and (b.type=="int" or b.type=="float") then
		return py_bool(a.value == b.value)
	end
	if a.type=="str" and b.type=="str" then return py_bool(a.value == b.value) end
	if a.type=="list" and b.type=="list" then
		if #a.value ~= #b.value then return py_false end
		for i=1,#a.value do
			if not Py.is_truthy(Py.eq(a.value[i], b.value[i])) then return py_false end
		end
		return py_true
	end
	return py_false
end
function Py.ne(a,b) return py_bool(not Py.is_truthy(Py.eq(a,b))) end
function Py.lt(a,b)
	if (a.type=="int" or a.type=="float") and (b.type=="int" or b.type=="float") then
		return py_bool(a.value < b.value)
	elseif a.type=="str" and b.type=="str" then
		return py_bool(a.value < b.value)
	end
	error("TypeError: '<' not supported between instances of "..a.type.." and "..b.type)
end
function Py.le(a,b)
	if (a.type=="int" or a.type=="float") and (b.type=="int" or b.type=="float") then
		return py_bool(a.value <= b.value)
	elseif a.type=="str" and b.type=="str" then
		return py_bool(a.value <= b.value)
	end
	error("TypeError: '<=' not supported")
end
function Py.gt(a,b) return py_bool(not Py.is_truthy(Py.le(a,b))) end
function Py.ge(a,b) return py_bool(not Py.is_truthy(Py.lt(a,b))) end

-- Operadores lógicos
function Py.not_op(a) return py_bool(not Py.is_truthy(a)) end
function Py.and_op(a,b) return Py.is_truthy(a) and b or a end
function Py.or_op(a,b) return Py.is_truthy(a) and a or b end

-- Indexación
function Py.getitem(obj, key)
	if obj.type=="str" then
		if key.type=="int" then
			local idx = key.value
			if idx<1 or idx>#obj.value then error("IndexError: string index out of range") end
			return py_str(obj.value:sub(idx,idx))
		end
		error("TypeError: string indices must be integers")
	elseif obj.type=="list" then
		if key.type=="int" then
			local idx = key.value
			if idx<1 or idx>#obj.value then error("IndexError: list index out of range") end
			return obj.value[idx]
		end
		error("TypeError: list indices must be integers")
	elseif obj.type=="dict" then
		local k = (key.type=="int" or key.type=="float") and key.value or key.value
		local v = obj.value[k]
		if v == nil then error("KeyError: "..Py.repr(key)) end
		return v
	end
	error("TypeError: '"..obj.type.."' object is not subscriptable")
end

function Py.setitem(obj, key, value)
	if obj.type=="list" then
		if key.type=="int" then
			local idx = key.value
			if idx<1 or idx>#obj.value then error("IndexError: list assignment index out of range") end
			obj.value[idx] = value
		else error("TypeError: list indices must be integers") end
	elseif obj.type=="dict" then
		local k = (key.type=="int" or key.type=="float") and key.value or key.value
		obj.value[k] = value
	else
		error("TypeError: '"..obj.type.."' object does not support item assignment")
	end
end

-- Llamada a función
function Py.call(func, args, kwargs)
	if func.type ~= "function" then error("TypeError: '"..func.type.."' object is not callable") end
	return func.value(args, kwargs or {})
end

-- ==============================================
-- ENTORNO GLOBAL (builtins y módulos)
-- ==============================================
local global_env = {variables={}, functions={}}

local function set_global(name, val)
	if val.type=="function" then
		global_env.functions[name] = val
	else
		global_env.variables[name] = val
	end
end

-- Builtins
set_global("None", py_none)
set_global("True", py_true)
set_global("False", py_false)

set_global("print", py_func(function(args)
	local strs = {}
	for _,v in ipairs(args) do
		table.insert(strs, v.type=="str" and v.value or Py.repr(v))
	end
	Py.output(table.concat(strs, " ").."\n")
	return py_none
end, "print"))

set_global("input", py_func(function(args)
	local prompt = args[1] and args[1].value or ""
	return Py.input_request(prompt)
end, "input"))

set_global("len", py_func(function(args)
	local obj = args[1]
	if obj.type=="str" then return py_int(#obj.value)
	elseif obj.type=="list" then return py_int(#obj.value)
	elseif obj.type=="dict" then
		local count=0
		for _ in pairs(obj.value) do count=count+1 end
		return py_int(count)
	else error("TypeError: object of type '"..obj.type.."' has no len()") end
end, "len"))

set_global("range", py_func(function(args)
	local start, stop, step = 0,0,1
	if #args==1 then stop=args[1].value
	elseif #args==2 then start=args[1].value; stop=args[2].value
	elseif #args==3 then start=args[1].value; stop=args[2].value; step=args[3].value end
	local lst={}
	for i=start,stop-1,step do table.insert(lst, py_int(i)) end
	return py_list(lst)
end, "range"))

set_global("int", py_func(function(args)
	if args[1].type=="int" then return args[1]
	elseif args[1].type=="float" then return py_int(math.floor(args[1].value))
	elseif args[1].type=="str" then return py_int(tonumber(args[1].value) or 0)
	else return py_int(0) end
end, "int"))

set_global("float", py_func(function(args)
	if args[1].type=="int" then return py_float(args[1].value)
	elseif args[1].type=="float" then return args[1]
	elseif args[1].type=="str" then return py_float(tonumber(args[1].value) or 0.0)
	else return py_float(0.0) end
end, "float"))

set_global("str", py_func(function(args)
	return py_str(Py.repr(args[1]))
end, "str"))

set_global("bool", py_func(function(args)
	return py_bool(Py.is_truthy(args[1]))
end, "bool"))

set_global("list", py_func(function(args)
	if args[1] and args[1].type=="list" then return py_list(args[1].value) end
	return py_list({})
end, "list"))

set_global("dict", py_func(function(args)
	return py_dict({})
end, "dict"))

set_global("type", py_func(function(args)
	return py_str(args[1].type)
end, "type"))

set_global("abs", py_func(function(args)
	local v = args[1]
	if v.type=="int" then return py_int(math.abs(v.value))
	elseif v.type=="float" then return py_float(math.abs(v.value))
	else error("TypeError: bad operand type for abs()") end
end, "abs"))

set_global("max", py_func(function(args)
	local best = args[1]
	for i=2,#args do
		if Py.is_truthy(Py.gt(args[i], best)) then best = args[i] end
	end
	return best
end, "max"))

set_global("min", py_func(function(args)
	local best = args[1]
	for i=2,#args do
		if Py.is_truthy(Py.lt(args[i], best)) then best = args[i] end
	end
	return best
end, "min"))

set_global("sum", py_func(function(args)
	local total = 0.0
	for _,v in ipairs(args[1].value) do
		total = total + v.value
	end
	return py_float(total)
end, "sum"))

set_global("sorted", py_func(function(args)
	local lst = {}
	for _,v in ipairs(args[1].value) do table.insert(lst, v) end
	table.sort(lst, function(a,b) return Py.is_truthy(Py.lt(a,b)) end)
	return py_list(lst)
end, "sorted"))

set_global("open", py_func(function(args)
	local filename = args[1].value
	local mode = args[2] and args[2].value or "r"
	return Py.file_open(filename, mode)
end, "open"))

set_global("help", py_func(function(args)
	Py.output("Help: use Python syntax\nBuiltins: print, input, len, range, int, float, str, bool, list, dict, type, abs, max, min, sum, sorted, open\nModules: os, math, requests, json, random, time\n")
	return py_none
end, "help"))

-- Módulo os
set_global("os.system", py_func(function(args)
	-- no hay shell real, simulamos
	Py.output("[os.system] "..args[1].value.."\n")
	return py_int(0)
end, "os.system"))

set_global("os.time", py_func(function()
	return py_int(os.time())
end, "os.time"))

set_global("os.getenv", py_func(function(args)
	return py_str("ROBLOX")
end, "os.getenv"))

set_global("os.name", py_str("roblox"))

-- Módulo requests
local function requests_get(args, kwargs)
	local url = args[1].value
	local success, result = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if success then
		return py_str(result)
	else
		error("requests.get: "..result)
	end
end
set_global("requests.get", py_func(requests_get, "requests.get"))
set_global("requests.post", py_func(function(args)
	local url = args[1].value
	local data = args[2] and args[2].value or ""
	local success, result = pcall(function()
		return HttpService:PostAsync(url, data)
	end)
	if success then return py_str(result) else error("requests.post failed") end
end, "requests.post"))

-- Módulo json
set_global("json.loads", py_func(function(args)
	local str = args[1].value
	local success, decoded = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	if success then
		-- convertir tabla Lua a dict/list recursivo
		local function to_py(obj)
			if type(obj)=="table" then
				-- comprobar si es array
				local is_array = true
				for k in pairs(obj) do
					if type(k)~="number" then is_array=false break end
				end
				if is_array then
					local arr = {}
					for i,v in ipairs(obj) do
						arr[i] = to_py(v)
					end
					return py_list(arr)
				else
					local d = {}
					for k,v in pairs(obj) do
						d[k] = to_py(v)
					end
					return py_dict(d)
				end
			elseif type(obj)=="string" then return py_str(obj)
			elseif type(obj)=="number" then return py_float(obj)
			elseif type(obj)=="boolean" then return py_bool(obj)
			else return py_none end
		end
		return to_py(decoded)
	else
		error("json.loads: "..decoded)
	end
end, "json.loads"))

set_global("json.dumps", py_func(function(args)
	local obj = args[1]
	local function from_py(v)
		if v.type=="none" then return nil
		elseif v.type=="bool" then return v.value
		elseif v.type=="int" then return v.value
		elseif v.type=="float" then return v.value
		elseif v.type=="str" then return v.value
		elseif v.type=="list" then
			local arr = {}
			for _,e in ipairs(v.value) do table.insert(arr, from_py(e)) end
			return arr
		elseif v.type=="dict" then
			local d = {}
			for k,val in pairs(v.value) do d[k] = from_py(val) end
			return d
		end
	end
	local lua_obj = from_py(obj)
	return py_str(HttpService:JSONEncode(lua_obj))
end, "json.dumps"))

-- Módulo math
set_global("math.pi", py_float(math.pi))
set_global("math.e", py_float(math.exp(1)))
set_global("math.sqrt", py_func(function(args) return py_float(math.sqrt(args[1].value)) end, "math.sqrt"))
set_global("math.sin", py_func(function(args) return py_float(math.sin(args[1].value)) end, "math.sin"))
set_global("math.cos", py_func(function(args) return py_float(math.cos(args[1].value)) end, "math.cos"))
set_global("math.tan", py_func(function(args) return py_float(math.tan(args[1].value)) end, "math.tan"))
set_global("math.log", py_func(function(args) return py_float(math.log(args[1].value)) end, "math.log"))
set_global("math.log10", py_func(function(args) return py_float(math.log10(args[1].value)) end, "math.log10"))
set_global("math.exp", py_func(function(args) return py_float(math.exp(args[1].value)) end, "math.exp"))
set_global("math.floor", py_func(function(args) return py_int(math.floor(args[1].value)) end, "math.floor"))
set_global("math.ceil", py_func(function(args) return py_int(math.ceil(args[1].value)) end, "math.ceil"))
set_global("math.fabs", py_func(function(args) return py_float(math.abs(args[1].value)) end, "math.fabs"))

-- Módulo random
local random = Random.new()
set_global("random.random", py_func(function() return py_float(random:NextNumber()) end, "random.random"))
set_global("random.randint", py_func(function(args) return py_int(random:NextInteger(args[1].value, args[2].value)) end, "random.randint"))
set_global("random.choice", py_func(function(args)
	local lst = args[1].value
	return lst[random:NextInteger(1,#lst)]
end, "random.choice"))

-- Módulo time (simular sleep con task.wait)
set_global("time.sleep", py_func(function(args)
	task.wait(args[1].value)
	return py_none
end, "time.sleep"))
set_global("time.time", py_func(function() return py_float(os.clock()) end, "time.time"))

-- Función window() para crear ventanas gráficas
set_global("window", py_func(function(args, kwargs)
	local title = args[1] and args[1].value or "Window"
	local width = kwargs and kwargs.width and kwargs.width.value or 400
	local height = kwargs and kwargs.height and kwargs.height.value or 300
	Py.create_window(title, width, height, kwargs)
	return py_none
end, "window"))

-- ==============================================
-- LEXER (tokenizador)
-- ==============================================
local TokenType = {
	EOF=0, NAME=1, NUMBER=2, STRING=3, OP=4, INDENT=5, DEDENT=6, NEWLINE=7,
	COMMENT=8, LPAR=9, RPAR=10, LSQB=11, RSQB=12, COLON=13, COMMA=14,
	SEMI=15, PLUS=16, MINUS=17, STAR=18, SLASH=19, VBAR=20, AMPER=21,
	LESS=22, GREATER=23, EQUAL=24, DOT=25, PERCENT=26, BACKSLASH=27,
	HASH=28, AT=29, CIRCUMFLEX=30, TILDE=31, EQEQUAL=32, NOTEQUAL=33,
	LESSEQUAL=34, GREATEREQUAL=35, LEFTSHIFT=36, RIGHTSHIFT=37,
	DOUBLESTAR=38, DOUBLESLASH=39, ATEQUAL=40, RARROW=41, ELLIPSIS=42,
	COLONEQUAL=43, EXCLAMATION=44, DOLLAR=45, LBRACE=46, RBRACE=47,
	BACKTICK=48, PIPE=49
}
local tok_names = {}
for k,v in pairs(TokenType) do tok_names[v]=k end

local function tokenize(code)
	local tokens = {}
	local pos = 1
	local line = 1
	local indentstack = {0}
	local function peek() return code:sub(pos,pos) end
	local function advance()
		local c = peek()
		pos = pos+1
		if c=="\n" then line=line+1 end
		return c
	end
	local function add(type, value)
		table.insert(tokens, {type=type, value=value, line=line})
	end

	local function skip_whitespace()
		while pos<=#code and (peek()==" " or peek()=="\t" or peek()=="\r") do
			advance()
		end
	end

	-- manejar indentación al inicio de línea
	local function handle_indentation()
		local col = 0
		local start = pos
		while pos<=#code and (peek()==" ") do
			col=col+1; advance()
		end
		if peek()=="\n" or peek()=="#" or col==0 and peek()~="\n" then
			-- línea en blanco o comentario, ignorar indentación
			pos = start
			return
		end
		local top = indentstack[#indentstack]
		if col > top then
			table.insert(indentstack, col)
			add(TokenType.INDENT, col)
		elseif col < top then
			while col < top do
				table.remove(indentstack)
				top = indentstack[#indentstack]
				add(TokenType.DEDENT, top)
				if col == top then break end
			end
			if col > top then error("IndentationError at line "..line) end
		end
	end

	-- escanear tokens
	while pos <= #code do
		skip_whitespace()
		if pos > #code then break end

		local c = peek()

		-- newline (manejar indentación al principio de la siguiente línea)
		if c=="\n" then
			advance()
			add(TokenType.NEWLINE, "\n")
			-- miramos si la siguiente línea empieza indentada
			local saved = pos
			skip_whitespace()
			if peek()~="\n" and peek()~="#" then
				handle_indentation()
			end
			pos = saved
		elseif c=="#" then
			-- comentario hasta fin de línea
			while pos<=#code and peek()~="\n" do advance() end
		elseif c=="'" or c=='"' then
			local quote = advance()
			local s = ""
			while pos<=#code and peek()~=quote do
				if peek()=="\\" then
					advance()
					local esc = advance()
					s = s..({n="\n", t="\t", ["\\"]="\\", ["'"]="'", ['"']='"'})[esc] or esc
				else
					s = s..advance()
				end
			end
			if peek()==quote then advance() else error("Unterminated string") end
			add(TokenType.STRING, s)
		elseif c:match("%d") then
			local num = ""
			while pos<=#code and peek():match("[%d.]") do num=num..advance() end
			if num:find("%.") then add(TokenType.NUMBER, tonumber(num))
			else add(TokenType.NUMBER, tonumber(num)) end
		elseif c:match("[a-zA-Z_]") then
			local name = advance()
			while pos<=#code and peek():match("[%w_]") do name=name..advance() end
			local keywords = {
				and="and", as="as", assert="assert", break="break", class="class",
				continue="continue", def="def", del="del", elif="elif", else="else",
				except="except", False="False", finally="finally", for="for",
				from="from", global="global", if="if", import="import", in="in",
				is="is", lambda="lambda", None="None", nonlocal="nonlocal",
				not="not", or="or", pass="pass", raise="raise", return="return",
				True="True", try="try", while="while", with="with", yield="yield",
			}
			if keywords[name] then
				add(TokenType.NAME, name) -- las keywords son NAME, el parser distingue
			else
				add(TokenType.NAME, name)
			end
		else
			-- operadores y símbolos
			local op = advance()
			local nxt = peek()
			if op=="=" and nxt=="=" then advance(); add(TokenType.EQEQUAL, "==")
			elseif op=="!" and nxt=="=" then advance(); add(TokenType.NOTEQUAL, "!=")
			elseif op=="<" and nxt=="=" then advance(); add(TokenType.LESSEQUAL, "<=")
			elseif op==">" and nxt=="=" then advance(); add(TokenType.GREATEREQUAL, ">=")
			elseif op=="<" and nxt=="<" then advance(); add(TokenType.LEFTSHIFT, "<<")
			elseif op==">" and nxt==">" then advance(); add(TokenType.RIGHTSHIFT, ">>")
			elseif op=="*" and nxt=="*" then advance(); add(TokenType.DOUBLESTAR, "**")
			elseif op=="/" and nxt=="/" then advance(); add(TokenType.DOUBLESLASH, "//")
			elseif op=="+" and nxt=="=" then advance(); add(TokenType.OP, "+=")
			elseif op=="-" and nxt=="=" then advance(); add(TokenType.OP, "-=")
			elseif op=="*" and nxt=="=" then advance(); add(TokenType.OP, "*=")
			elseif op=="/" and nxt=="=" then advance(); add(TokenType.OP, "/=")
			elseif op=="%" and nxt=="=" then advance(); add(TokenType.OP, "%=")
			elseif op=="@" and nxt=="=" then advance(); add(TokenType.ATEQUAL, "@=")
			elseif op==":" and nxt=="=" then advance(); add(TokenType.COLONEQUAL, ":=")
			else
				-- mapear símbolo simple
				local simple = {
					["+"]=TokenType.PLUS, ["-"]=TokenType.MINUS, ["*"]=TokenType.STAR,
					["/"]=TokenType.SLASH, ["%"]=TokenType.PERCENT, ["^"]=TokenType.CIRCUMFLEX,
					["~"]=TokenType.TILDE, ["|"]=TokenType.VBAR, ["&"]=TokenType.AMPER,
					["<"]=TokenType.LESS, [">"]=TokenType.GREATER, ["="]=TokenType.EQUAL,
					["("]=TokenType.LPAR, [")"]=TokenType.RPAR, ["["]=TokenType.LSQB,
					["]"]=TokenType.RSQB, ["{"]=TokenType.LBRACE, ["}"]=TokenType.RBRACE,
					[","]=TokenType.COMMA, [":"]=TokenType.COLON, ["."]=TokenType.DOT,
					[";"]=TokenType.SEMI, ["@"]=TokenType.AT, ["#"]=TokenType.HASH,
					["\\"]=TokenType.BACKSLASH, ["`"]=TokenType.BACKTICK, ["$"]=TokenType.DOLLAR,
					["!"]=TokenType.EXCLAMATION,
				}
				local t = simple[op]
				if t then add(t, op) else error("Unknown character "..op.." at line "..line) end
			end
		end
	end
	-- DEDENTs finales
	while #indentstack > 1 do
		table.remove(indentstack)
		add(TokenType.DEDENT, indentstack[#indentstack])
	end
	add(TokenType.EOF, nil)
	return tokens
end

-- ==============================================
-- PARSER (recursive descent)
-- ==============================================
local Parser = {}
Parser.__index = Parser

function Parser.new(tokens)
	local self = setmetatable({}, Parser)
	self.tokens = tokens
	self.pos = 1
	self.indent = 0
	return self
end

function Parser:peek()
	return self.tokens[self.pos]
end

function Parser:advance()
	local tok = self.tokens[self.pos]
	self.pos = self.pos + 1
	return tok
end

function Parser:expect(type, value)
	local tok = self:peek()
	if tok.type ~= type or (value and tok.value ~= value) then
		error(string.format("SyntaxError: expected %s, got %s (%s) at line %d",
			tok_names[type] or type, tok_names[tok.type] or tok.type, tostring(tok.value), tok.line))
	end
	return self:advance()
end

function Parser:match(type, value)
	local tok = self:peek()
	if tok.type == type and (not value or tok.value == value) then
		return self:advance()
	end
	return nil
end

-- Gramática simplificada
function Parser:parse()
	local stmts = {}
	while self:peek().type ~= TokenType.EOF do
		if self:peek().type == TokenType.NEWLINE then
			self:advance()
		elseif self:peek().type == TokenType.INDENT then
			self:advance()
		elseif self:peek().type == TokenType.DEDENT then
			self:advance()
			break -- dedent termina bloque
		else
			table.insert(stmts, self:statement())
			if self:peek().type == TokenType.NEWLINE then self:advance() end
		end
	end
	return {type="block", stmts=stmts}
end

-- statement: simple_statement | compound_statement
function Parser:statement()
	local tok = self:peek()
	if tok.type == TokenType.NAME then
		local name = tok.value
		if name=="if" then return self:if_statement()
		elseif name=="while" then return self:while_statement()
		elseif name=="for" then return self:for_statement()
		elseif name=="def" then return self:func_def()
		elseif name=="class" then return self:class_def()
		elseif name=="return" then return self:return_statement()
		elseif name=="break" then self:advance(); return {type="break"}
		elseif name=="continue" then self:advance(); return {type="continue"}
		elseif name=="pass" then self:advance(); return {type="pass"}
		elseif name=="import" then return self:import_statement()
		elseif name=="from" then return self:from_import()
		else
			return self:simple_statement()
		end
	elseif tok.type == TokenType.OP then -- += etc
		-- augment assignment
		local target = self:expr()
		local op = self:advance().value
		local value = self:test()
		return {type="augassign", target=target, op=op, value=value}
	else
		return self:simple_statement()
	end
end

function Parser:simple_statement()
	local exp = self:expr_list()
	if self:peek().type == TokenType.EQUAL then
		self:advance()
		local value = self:expr_list()
		return {type="assign", targets=exp, value=value}
	elseif self:peek().type == TokenType.COLONEQUAL then
		self:advance()
		local value = self:test()
		return {type="annassign", target=exp[1], value=value} -- simplificado
	else
		-- expression statement
		return {type="expr", value=exp[1]} -- solo la primera
	end
end

function Parser:expr_list()
	local exprs = {self:test()}
	while self:match(TokenType.COMMA) do
		table.insert(exprs, self:test())
	end
	return exprs
end

-- if/elif/else
function Parser:if_statement()
	self:advance() -- 'if'
	local test = self:test()
	self:expect(TokenType.COLON)
	local body = self:suite()
	local orelse = {}
	local tok = self:peek()
	while tok.type==TokenType.NAME and tok.value=="elif" do
		self:advance()
		local test2 = self:test()
		self:expect(TokenType.COLON)
		local body2 = self:suite()
		table.insert(orelse, {type="elif", test=test2, body=body2})
		tok = self:peek()
	end
	if tok.type==TokenType.NAME and tok.value=="else" then
		self:advance()
		self:expect(TokenType.COLON)
		local elsebody = self:suite()
		table.insert(orelse, {type="else", body=elsebody})
	end
	return {type="if", test=test, body=body, orelse=orelse}
end

function Parser:while_statement()
	self:advance()
	local test = self:test()
	self:expect(TokenType.COLON)
	local body = self:suite()
	return {type="while", test=test, body=body}
end

function Parser:for_statement()
	self:advance()
	local target = self:expr_list()
	self:expect(TokenType.NAME, "in")
	local iter = self:expr_list()
	self:expect(TokenType.COLON)
	local body = self:suite()
	return {type="for", target=target, iter=iter, body=body}
end

function Parser:func_def()
	self:advance()
	local name = self:expect(TokenType.NAME).value
	self:expect(TokenType.LPAR)
	local params = {}
	if self:peek().type ~= TokenType.RPAR then
		params = self:expr_list() -- really just names, but expr_list works
	end
	self:expect(TokenType.RPAR)
	self:expect(TokenType.COLON)
	local body = self:suite()
	return {type="def", name=name, params=params, body=body}
end

function Parser:class_def()
	self:advance()
	local name = self:expect(TokenType.NAME).value
	local bases = {}
	if self:peek().type == TokenType.LPAR then
		self:advance()
		if self:peek().type ~= TokenType.RPAR then
			bases = self:expr_list()
		end
		self:expect(TokenType.RPAR)
	end
	self:expect(TokenType.COLON)
	local body = self:suite()
	return {type="class", name=name, bases=bases, body=body}
end

function Parser:return_statement()
	self:advance()
	if self:peek().type == TokenType.NEWLINE or self:peek().type == TokenType.DEDENT then
		return {type="return", value=py_none}
	else
		local val = self:test()
		return {type="return", value=val}
	end
end

function Parser:import_statement()
	self:advance()
	local names = {}
	repeat
		local mod = self:expect(TokenType.NAME).value
		local asname = mod
		if self:match(TokenType.NAME, "as") then
			asname = self:expect(TokenType.NAME).value
		end
		table.insert(names, {module=mod, as=asname})
	until not self:match(TokenType.COMMA)
	return {type="import", names=names}
end

function Parser:from_import()
	self:advance()
	local mod = self:expect(TokenType.NAME).value
	self:expect(TokenType.NAME, "import")
	local names = {}
	repeat
		local name = self:expect(TokenType.NAME).value
		local asname = name
		if self:match(TokenType.NAME, "as") then
			asname = self:expect(TokenType.NAME).value
		end
		table.insert(names, {name=name, as=asname})
	until not self:match(TokenType.COMMA)
	return {type="from_import", module=mod, names=names}
end

function Parser:suite()
	-- esperar NEWLINE e INDENT o simple statement
	if self:match(TokenType.NEWLINE) then
		self:expect(TokenType.INDENT)
		local stmts = {}
		while self:peek().type ~= TokenType.DEDENT and self:peek().type ~= TokenType.EOF do
			if self:peek().type == TokenType.NEWLINE then
				self:advance()
			else
				table.insert(stmts, self:statement())
				if self:peek().type == TokenType.NEWLINE then self:advance() end
			end
		end
		self:expect(TokenType.DEDENT)
		return {type="block", stmts=stmts}
	else
		local stmt = self:simple_statement()
		return {type="block", stmts={stmt}}
	end
end

-- expression parsing (precedence climbing)
function Parser:test()
	return self:or_expr()
end

function Parser:or_expr()
	local left = self:and_expr()
	while self:match(TokenType.NAME, "or") do
		local right = self:and_expr()
		left = {type="binop", op="or", left=left, right=right}
	end
	return left
end

function Parser:and_expr()
	local left = self:not_expr()
	while self:match(TokenType.NAME, "and") do
		local right = self:not_expr()
		left = {type="binop", op="and", left=left, right=right}
	end
	return left
end

function Parser:not_expr()
	if self:match(TokenType.NAME, "not") then
		local operand = self:not_expr()
		return {type="unaryop", op="not", operand=operand}
	end
	return self:comparison()
end

function Parser:comparison()
	local left = self:arith_expr()
	while self:peek().type == TokenType.EQEQUAL or self:peek().type == TokenType.NOTEQUAL
		or self:peek().type == TokenType.LESS or self:peek().type == TokenType.GREATER
		or self:peek().type == TokenType.LESSEQUAL or self:peek().type == TokenType.GREATEREQUAL
		or (self:peek().type==TokenType.NAME and (self:peek().value=="in" or self:peek().value=="is")) do
		local op = self:advance().value
		local right = self:arith_expr()
		left = {type="compare", left=left, op=op, right=right}
	end
	return left
end

function Parser:arith_expr()
	local left = self:term()
	while self:peek().type==TokenType.PLUS or self:peek().type==TokenType.MINUS do
		local op = self:advance().value
		local right = self:term()
		left = {type="binop", op=op, left=left, right=right}
	end
	return left
end

function Parser:term()
	local left = self:factor()
	while self:peek().type==TokenType.STAR or self:peek().type==TokenType.SLASH
		or self:peek().type==TokenType.DOUBLESLASH or self:peek().type==TokenType.PERCENT do
		local op = self:advance().value
		local right = self:factor()
		left = {type="binop", op=op, left=left, right=right}
	end
	return left
end

function Parser:factor()
	if self:match(TokenType.PLUS) then
		return self:factor()
	elseif self:match(TokenType.MINUS) then
		local operand = self:factor()
		return {type="unaryop", op="-", operand=operand}
	elseif self:match(TokenType.TILDE) then
		local operand = self:factor()
		return {type="unaryop", op="~", operand=operand}
	end
	return self:power()
end

function Parser:power()
	local left = self:atom()
	if self:peek().type == TokenType.DOUBLESTAR then
		self:advance()
		local right = self:factor() -- right associativity
		left = {type="binop", op="**", left=left, right=right}
	end
	-- trailers (call, index, dot)
	while true do
		local tok = self:peek()
		if tok.type == TokenType.LPAR then
			self:advance()
			local args = {}
			if self:peek().type ~= TokenType.RPAR then
				args = self:expr_list()
			end
			self:expect(TokenType.RPAR)
			left = {type="call", func=left, args=args}
		elseif tok.type == TokenType.LSQB then
			self:advance()
			local idx = self:test()
			self:expect(TokenType.RSQB)
			left = {type="subscript", value=left, index=idx}
		elseif tok.type == TokenType.DOT then
			self:advance()
			local attr = self:expect(TokenType.NAME).value
			left = {type="attribute", value=left, attr=attr}
		else
			break
		end
	end
	return left
end

function Parser:atom()
	local tok = self:peek()
	if tok.type == TokenType.NAME then
		local name = tok.value
		self:advance()
		if name=="None" then return {type="literal", value=py_none}
		elseif name=="True" then return {type="literal", value=py_true}
		elseif name=="False" then return {type="literal", value=py_false}
		else return {type="name", id=name} end
	elseif tok.type == TokenType.NUMBER then
		self:advance()
		local n = tok.value
		if n==math.floor(n) then return {type="literal", value=py_int(n)}
		else return {type="literal", value=py_float(n)} end
	elseif tok.type == TokenType.STRING then
		self:advance()
		return {type="literal", value=py_str(tok.value)}
	elseif tok.type == TokenType.LPAR then
		self:advance()
		local e = self:test()
		self:expect(TokenType.RPAR)
		return e
	elseif tok.type == TokenType.LSQB then
		return self:list_display()
	elseif tok.type == TokenType.LBRACE then
		return self:dict_display()
	else
		error("SyntaxError at line "..tok.line..": unexpected "..tok_names[tok.type])
	end
end

function Parser:list_display()
	self:advance() -- '['
	local elements = {}
	if self:peek().type ~= TokenType.RSQB then
		elements = self:expr_list()
	end
	self:expect(TokenType.RSQB)
	return {type="list", elements=elements}
end

function Parser:dict_display()
	self:advance() -- '{'
	local items = {}
	if self:peek().type ~= TokenType.RBRACE then
		repeat
			local key = self:test()
			self:expect(TokenType.COLON)
			local value = self:test()
			table.insert(items, {key=key, value=value})
		until not self:match(TokenType.COMMA)
	end
	self:expect(TokenType.RBRACE)
	return {type="dict", items=items}
end

-- ==============================================
-- EVALUADOR (interprete)
-- ==============================================
local Eval = {}
Eval.__index = Eval

function Eval.new(env)
	local self = setmetatable({}, Eval)
	self.globals = env
	self.locals = {}
	return self
end

function Eval:push_scope()
	table.insert(self.locals, {})
end

function Eval:pop_scope()
	table.remove(self.locals)
end

function Eval:get_var(name)
	for i=#self.locals,1,-1 do
		local v = self.locals[i][name]
		if v ~= nil then return v end
	end
	local v = self.globals.variables[name] or self.globals.functions[name]
	if v then return v end
	error("NameError: name '"..name.."' is not defined")
end

function Eval:set_var(name, val)
	for i=#self.locals,1,-1 do
		if self.locals[i][name] ~= nil then
			self.locals[i][name] = val
			return
		end
	end
	self.globals.variables[name] = val
end

function Eval:eval(node)
	if not node then return py_none end
	local t = node.type
	if t=="block" then
		return self:eval_block(node)
	elseif t=="assign" then
		local value = self:eval(node.value)
		for _,target in ipairs(node.targets) do
			self:assign_target(target, value)
		end
		return py_none
	elseif t=="expr" then
		return self:eval(node.value)
	elseif t=="if" then
		return self:eval_if(node)
	elseif t=="while" then
		return self:eval_while(node)
	elseif t=="for" then
		return self:eval_for(node)
	elseif t=="def" then
		return self:eval_def(node)
	elseif t=="return" then
		local val = node.value and self:eval(node.value) or py_none
		-- return saliendo de función, se maneja con un flag
		self.return_value = val
		return val
	elseif t=="break" then
		self.break_flag = true
		return py_none
	elseif t=="continue" then
		self.continue_flag = true
		return py_none
	elseif t=="import" then
		return self:eval_import(node)
	elseif t=="from_import" then
		return self:eval_from_import(node)
	elseif t=="augassign" then
		local target = node.target
		local lhs = self:eval(target)
		local rhs = self:eval(node.value)
		local op = node.op:sub(1,1) -- solo + - * / etc
		local result
		if op=="+" then result = Py.add(lhs,rhs)
		elseif op=="-" then result = Py.sub(lhs,rhs)
		elseif op=="*" then result = Py.mul(lhs,rhs)
		elseif op=="/" then result = Py.truediv(lhs,rhs)
		elseif op=="%" then result = Py.mod(lhs,rhs)
		elseif op=="^" then result = Py.pow(lhs,rhs)
		else error("unknown augassign") end
		self:assign_target(target, result)
		return py_none
	-- expressions
	elseif t=="name" then
		return self:get_var(node.id)
	elseif t=="literal" then
		return node.value
	elseif t=="binop" then
		local left = self:eval(node.left)
		local right = self:eval(node.right)
		local op = node.op
		if op=="+" then return Py.add(left,right)
		elseif op=="-" then return Py.sub(left,right)
		elseif op=="*" then return Py.mul(left,right)
		elseif op=="/" then return Py.truediv(left,right)
		elseif op=="//" then return Py.floordiv(left,right)
		elseif op=="%" then return Py.mod(left,right)
		elseif op=="**" then return Py.pow(left,right)
		elseif op=="and" then return Py.and_op(left,right)
		elseif op=="or" then return Py.or_op(left,right)
		end
	elseif t=="unaryop" then
		local operand = self:eval(node.operand)
		if node.op=="not" then return Py.not_op(operand)
		elseif node.op=="-" then return Py.sub(py_int(0), operand)
		elseif node.op=="~" then return py_int(bit32.bnot(operand.value)) end
	elseif t=="compare" then
		local left = self:eval(node.left)
		local right = self:eval(node.right)
		local op = node.op
		if op=="==" then return Py.eq(left,right)
		elseif op=="!=" then return Py.ne(left,right)
		elseif op=="<" then return Py.lt(left,right)
		elseif op=="<=" then return Py.le(left,right)
		elseif op==">" then return Py.gt(left,right)
		elseif op==">=" then return Py.ge(left,right)
		elseif op=="in" then -- iterar
			if right.type=="list" then
				for _,v in ipairs(right.value) do
					if Py.is_truthy(Py.eq(left,v)) then return py_true end
				end
				return py_false
			else error("TypeError") end
		end
	elseif t=="call" then
		local func = self:eval(node.func)
		local args = {}
		for _,a in ipairs(node.args) do table.insert(args, self:eval(a)) end
		return Py.call(func, args, {})
	elseif t=="subscript" then
		local obj = self:eval(node.value)
		local idx = self:eval(node.index)
		return Py.getitem(obj, idx)
	elseif t=="attribute" then
		local obj = self:eval(node.value)
		local attr = node.attr
		if obj.type=="module" then
			return obj.value[attr] or error("AttributeError")
		elseif obj.type=="dict" then
			return obj.value[attr] or error("KeyError")
		else
			error("TypeError: attribute access not supported")
		end
	elseif t=="list" then
		local vals = {}
		for _,e in ipairs(node.elements) do table.insert(vals, self:eval(e)) end
		return py_list(vals)
	elseif t=="dict" then
		local d = {}
		for _,item in ipairs(node.items) do
			local k = self:eval(item.key)
			local v = self:eval(item.value)
			local lk = (k.type=="int" or k.type=="float") and k.value or k.value
			d[lk] = v
		end
		return py_dict(d)
	end
	error("Unknown node type "..t)
end

function Eval:eval_block(block)
	self:push_scope()
	for _,stmt in ipairs(block.stmts) do
		if self.return_value or self.break_flag or self.continue_flag then break end
		self:eval(stmt)
	end
	self:pop_scope()
end

function Eval:assign_target(target, value)
	if target.type=="name" then
		self:set_var(target.id, value)
	elseif target.type=="subscript" then
		local obj = self:eval(target.value)
		local idx = self:eval(target.index)
		Py.setitem(obj, idx, value)
	elseif target.type=="attribute" then
		local obj = self:eval(target.value)
		-- simplificado, asignar a campo de dict
		obj.value[target.attr] = value
	end
end

function Eval:eval_if(node)
	if Py.is_truthy(self:eval(node.test)) then
		self:eval_block(node.body)
	else
		for _,clause in ipairs(node.orelse) do
			if clause.type=="elif" and Py.is_truthy(self:eval(clause.test)) then
				self:eval_block(clause.body)
				return
			elseif clause.type=="else" then
				self:eval_block(clause.body)
				return
			end
		end
	end
end

function Eval:eval_while(node)
	while true do
		if not Py.is_truthy(self:eval(node.test)) then break end
		self:eval_block(node.body)
		if self.break_flag then self.break_flag = false; break end
		if self.continue_flag then self.continue_flag = false end
	end
end

function Eval:eval_for(node)
	local iter = self:eval(node.iter[1]) -- asumimos un iterable
	if iter.type=="list" then
		for _,v in ipairs(iter.value) do
			self:assign_target(node.target[1], v)
			self:eval_block(node.body)
			if self.break_flag then self.break_flag=false; break end
			if self.continue_flag then self.continue_flag=false end
		end
	elseif iter.type=="str" then
		for i=1,#iter.value do
			self:assign_target(node.target[1], py_str(iter.value:sub(i,i)))
			self:eval_block(node.body)
			if self.break_flag then self.break_flag=false; break end
			if self.continue_flag then self.continue_flag=false end
		end
	else
		error("TypeError: object not iterable")
	end
end

function Eval:eval_def(node)
	local func = py_func(function(args, kwargs)
		local subeval = Eval.new(global_env) -- usar entorno global pero con locales nuevos
		subeval:push_scope()
		-- asignar parámetros
		for i,param in ipairs(node.params) do
			local name = param.id
			subeval.locals[#subeval.locals][name] = args[i] or py_none
		end
		subeval:eval_block(node.body)
		local ret = subeval.return_value or py_none
		subeval:pop_scope()
		return ret
	end, node.name)
	self:set_var(node.name, func)
	return py_none
end

function Eval:eval_import(node)
	for _,imp in ipairs(node.names) do
		local mod = imp.module
		local found = global_env.variables[mod] or global_env.functions[mod]
		if not found then
			error("ImportError: No module named '"..mod.."'")
		end
		self:set_var(imp.as, found)
	end
	return py_none
end

function Eval:eval_from_import(node)
	local mod = node.module
	local mod_obj = global_env.variables[mod] or global_env.functions[mod]
	if not mod_obj then error("ImportError: No module named '"..mod.."'") end
	for _,name in ipairs(node.names) do
		local val
		if mod_obj.type=="module" then
			val = mod_obj.value[name.name]
		else
			-- asumimos que es un dict de funciones
			val = mod_obj.value[name.name]
		end
		if not val then error("ImportError: cannot import name '"..name.name.."'") end
		self:set_var(name.as, val)
	end
	return py_none
end

function Eval:eval_file(code)
	local tokens = tokenize(code)
	local parser = Parser.new(tokens)
	local ast = parser:parse()
	self.return_value = nil
	self.break_flag = false
	self.continue_flag = false
	self:eval_block(ast)
end

-- ==============================================
-- INTERFAZ TERMINAL (GUI)
-- ==============================================
local screenGui = Instance.new("ScreenGui", Player:WaitForChild("PlayerGui"))
screenGui.Name = "PythonTerminal"

-- Ventana principal
local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Size = UDim2.new(0,650,0,420)
mainFrame.Position = UDim2.new(0.5,-325,0.5,-210)
mainFrame.BackgroundColor3 = Color3.fromRGB(20,20,20)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true

-- Barra de título
local titleBar = Instance.new("Frame", mainFrame)
titleBar.Size = UDim2.new(1,0,0,28)
titleBar.BackgroundColor3 = Color3.fromRGB(40,40,40)
titleBar.BorderSizePixel = 0

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size = UDim2.new(0,200,1,0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "🐍 Python Terminal (Linux)"
titleLabel.TextColor3 = Color3.fromRGB(200,200,200)
titleLabel.Font = Enum.Font.Code
titleLabel.TextSize = 14
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Position = UDim2.new(0,8,0,0)

-- Botones cerrar/minimizar
local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size = UDim2.new(0,28,1,0)
closeBtn.Position = UDim2.new(1,-28,0,0)
closeBtn.Text = "✕"
closeBtn.BackgroundColor3 = Color3.fromRGB(220,50,50)
closeBtn.TextColor3 = Color3.new(1,1,1)
closeBtn.Font = Enum.Font.Code
closeBtn.TextSize = 16
closeBtn.MouseButton1Click:Connect(function() screenGui:Destroy() end)

local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0,28,1,0)
minBtn.Position = UDim2.new(1,-56,0,0)
minBtn.Text = "─"
minBtn.BackgroundColor3 = Color3.fromRGB(80,80,80)
minBtn.TextColor3 = Color3.new(1,1,1)
minBtn.Font = Enum.Font.Code
minBtn.TextSize = 16
local bodyVisible = true
minBtn.MouseButton1Click:Connect(function()
	bodyVisible = not bodyVisible
	editor.Visible = bodyVisible
	console.Visible = bodyVisible
	runButton.Visible = bodyVisible
end)

-- Área del editor
local editor = Instance.new("TextBox", mainFrame)
editor.Size = UDim2.new(1,-8,0.45,-2)
editor.Position = UDim2.new(0,4,0,30)
editor.BackgroundColor3 = Color3.fromRGB(15,15,15)
editor.TextColor3 = Color3.fromRGB(230,230,230)
editor.Font = Enum.Font.Code
editor.TextSize = 13
editor.ClearTextOnFocus = false
editor.MultiLine = true
editor.TextWrapped = false
editor.Text = 'print("Hello Roblox Python!")'
editor.BorderSizePixel = 0

-- Consola de salida
local console = Instance.new("ScrollingFrame", mainFrame)
console.Size = UDim2.new(1,-8,0.45,-2)
console.Position = UDim2.new(0,4,0.5,30)
console.BackgroundColor3 = Color3.fromRGB(0,0,0)
console.BorderSizePixel = 0
console.ScrollBarThickness = 6
console.CanvasSize = UDim2.new(0,0,0,0)
console.BottomImage = ""

local outputLabel = Instance.new("TextLabel", console)
outputLabel.Size = UDim2.new(1,0,1,0)
outputLabel.BackgroundTransparency = 1
outputLabel.TextColor3 = Color3.fromRGB(0,255,0)
outputLabel.Font = Enum.Font.Code
outputLabel.TextSize = 13
outputLabel.TextXAlignment = Enum.TextXAlignment.Left
outputLabel.TextYAlignment = Enum.TextYAlignment.Top
outputLabel.TextWrapped = true

-- Botón ejecutar
local runButton = Instance.new("TextButton", mainFrame)
runButton.Size = UDim2.new(0,80,0,24)
runButton.Position = UDim2.new(1,-86,1,-26)
runButton.Text = "▶ Run (F5)"
runButton.BackgroundColor3 = Color3.fromRGB(0,130,0)
runButton.TextColor3 = Color3.new(1,1,1)
runButton.Font = Enum.Font.Code
runButton.TextSize = 13
runButton.BorderSizePixel = 0

-- Variables globales para el intérprete
local py_out = ""
function Py.output(msg)
	py_out = py_out .. msg
	outputLabel.Text = py_out
	console.CanvasSize = UDim2.new(0,0,0,outputLabel.TextBounds.Y+20)
end

-- Simular input con un popup básico (bloquea hasta que se ingrese)
function Py.input_request(prompt)
	-- No podemos bloquear realmente, así que devolvemos cadena vacía o podríamos usar un diálogo asíncrono.
	-- Para simplicidad, devolvemos "input_placeholder"
	Py.output(prompt)
	return py_str("")
end

-- Crear ventana gráfica (ejemplo)
function Py.create_window(title, w, h, kwargs)
	local win = Instance.new("Frame", screenGui)
	win.Size = UDim2.new(0,w,0,h)
	win.Position = UDim2.new(math.random()*0.8,0,math.random()*0.8,0)
	win.BackgroundColor3 = Color3.fromRGB(40,40,40)
	win.BorderSizePixel = 0
	local top = Instance.new("Frame", win)
	top.Size = UDim2.new(1,0,0,24)
	top.BackgroundColor3 = Color3.fromRGB(60,60,60)
	local lbl = Instance.new("TextLabel", top)
	lbl.Text = title
	lbl.Size = UDim2.new(1,0,1,0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.new(1,1,1)
	lbl.Font = Enum.Font.Code
	local close = Instance.new("TextButton", top)
	close.Text = "X"; close.Size = UDim2.new(0,22,1,0); close.Position = UDim2.new(1,-22,0,0)
	close.BackgroundColor3 = Color3.fromRGB(200,50,50)
	close.TextColor3 = Color3.new(1,1,1)
	close.MouseButton1Click:Connect(function() win:Destroy() end)
	-- permitir arrastrar
	local drag = false; local dStart, sPos
	top.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			drag=true; dStart=inp.Position; sPos=win.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if drag and inp.UserInputType==Enum.UserInputType.MouseMovement then
			local d = inp.Position - dStart
			win.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset+d.X, sPos.Y.Scale, sPos.Y.Offset+d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then drag=false end
	end)
end

-- Arrastrar terminal principal
local dragTerm = false; local termStart, termPos
titleBar.InputBegan:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		dragTerm=true; termStart=inp.Position; termPos=mainFrame.Position
	end
end)
UserInputService.InputChanged:Connect(function(inp)
	if dragTerm and inp.UserInputType==Enum.UserInputType.MouseMovement then
		local d = inp.Position - termStart
		mainFrame.Position = UDim2.new(termPos.X.Scale, termPos.X.Offset+d.X, termPos.Y.Scale, termPos.Y.Offset+d.Y)
	end
end)
UserInputService.InputEnded:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragTerm=false end
end)

-- Ejecutar código al presionar Run o F5
local function execute()
	py_out = ""
	outputLabel.Text = ""
	local code = editor.Text
	local eval = Eval.new(global_env)
	local success, err = pcall(function()
		eval:eval_file(code)
	end)
	if not success then
		Py.output("Error: "..tostring(err).."\n")
	end
end

runButton.MouseButton1Click:Connect(execute)
UserInputService.InputBegan:Connect(function(inp, gpe)
	if gpe then return end
	if inp.KeyCode == Enum.KeyCode.F5 then
		execute()
	end
end)

-- Mensaje inicial
Py.output("Python Terminal for Roblox v1.0\nType Python code and press Run (F5).\n")