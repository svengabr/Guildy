// Reads and writes WoW SavedVariables files (Lua assignments of table constructors).
// Strings are byte strings: read the file as latin1 and write it as latin1, so UTF-8 names survive
// unchanged. A Lua table is a LuaTable: positional values in `arr`, keyed values in `hash` (a Map
// with number, string or boolean keys).

export class LuaTable {
  constructor() {
    this.arr = []
    this.hash = new Map()
  }
  get(key) { return this.hash.get(key) }
  set(key, value) {
    if (value === undefined || value === null) this.hash.delete(key)
    else this.hash.set(key, value)
  }
  has(key) { return this.hash.has(key) }
  keys() { return [...this.hash.keys()] }
  // Table under key, created when missing
  table(key) {
    let t = this.hash.get(key)
    if (!(t instanceof LuaTable)) {
      t = new LuaTable()
      this.hash.set(key, t)
    }
    return t
  }
}

// Plain object/array to LuaTable (numeric-looking object keys of `numeric` objects become numbers)
export function toLua(value) {
  if (value instanceof LuaTable || value === null || typeof value !== 'object') return value
  const t = new LuaTable()
  if (Array.isArray(value)) {
    t.arr = value.map(toLua)
    return t
  }
  for (const [k, v] of Object.entries(value)) {
    const key = /^-?\d+$/.test(k) ? Number(k) : k
    t.set(key, toLua(v))
  }
  return t
}

// Parses a SavedVariables file into a Map of global name -> value
export function parse(text) {
  let i = 0
  const n = text.length
  const fail = msg => { throw new Error(`${msg} at offset ${i}: ${JSON.stringify(text.slice(i, i + 40))}`) }

  function skip() {
    for (;;) {
      while (i < n && /\s/.test(text[i])) i++
      if (text.startsWith('--', i)) {
        const long = text.slice(i + 2).match(/^\[(=*)\[/)
        if (long) {
          const close = `]${long[1]}]`
          const end = text.indexOf(close, i)
          if (end < 0) fail('unclosed comment')
          i = end + close.length
        } else {
          const end = text.indexOf('\n', i)
          i = end < 0 ? n : end + 1
        }
        continue
      }
      return
    }
  }

  function string() {
    const quote = text[i++]
    let out = ''
    while (i < n && text[i] !== quote) {
      let c = text[i++]
      if (c === '\\') {
        c = text[i++]
        if (c === 'n') out += '\n'
        else if (c === 'r') out += '\r'
        else if (c === 't') out += '\t'
        else if (c === 'a') out += '\x07'
        else if (c === 'b') out += '\b'
        else if (c === 'f') out += '\f'
        else if (c === 'v') out += '\v'
        else if (c === '\n') out += '\n'
        else if (/\d/.test(c)) {
          let digits = c
          while (digits.length < 3 && /\d/.test(text[i])) digits += text[i++]
          out += String.fromCharCode(Number(digits))
        } else out += c
      } else out += c
    }
    if (text[i] !== quote) fail('unclosed string')
    i++
    return out
  }

  function value() {
    skip()
    const c = text[i]
    if (c === '{') return table()
    if (c === '"' || c === "'") return string()
    const m = text.slice(i, i + 64).match(/^(-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?|inf|nan)|true|false|nil)/)
    if (!m) fail('unexpected value')
    i += m[0].length
    if (m[0] === 'true') return true
    if (m[0] === 'false') return false
    if (m[0] === 'nil') return null
    return Number(m[0].replace(/^(-?)inf$/, '$1Infinity'))
  }

  function table() {
    i++ // {
    const t = new LuaTable()
    for (;;) {
      skip()
      if (text[i] === '}') { i++; return t }
      if (text[i] === '[') {
        i++
        const key = value()
        skip()
        if (text[i] !== ']') fail('expected ]')
        i++
        skip()
        if (text[i] !== '=') fail('expected =')
        i++
        t.set(key, value())
      } else {
        const name = text.slice(i).match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)/)
        if (name && !['true', 'false', 'nil'].includes(name[1])) {
          i += name[0].length
          t.set(name[1], value())
        } else {
          t.arr.push(value())
        }
      }
      skip()
      if (text[i] === ',' || text[i] === ';') i++
      else if (text[i] !== '}') fail('expected , or }')
    }
  }

  const globals = new Map()
  for (;;) {
    skip()
    if (i >= n) return globals
    const name = text.slice(i).match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=/)
    if (!name) fail('expected assignment')
    i += name[0].length
    globals.set(name[1], value())
  }
}

function quote(s) {
  let out = '"'
  for (let k = 0; k < s.length; k++) {
    const c = s[k]
    const code = s.charCodeAt(k)
    if (c === '"') out += '\\"'
    else if (c === '\\') out += '\\\\'
    else if (c === '\n') out += '\\n'
    else if (c === '\r') out += '\\r'
    else if (code < 32 || code === 127) out += '\\' + String(code).padStart(3, '0')
    else out += c
  }
  return out + '"'
}

function number(x) {
  if (Number.isNaN(x)) return '0/0'
  if (x === Infinity) return 'math.huge'
  if (x === -Infinity) return '-math.huge'
  return String(x)
}

function key(k) {
  return typeof k === 'string' ? `[${quote(k)}]` : `[${typeof k === 'number' ? number(k) : k}]`
}

function write(v, out) {
  if (v instanceof LuaTable) {
    out.push('{\n')
    for (const item of v.arr) {
      write(item, out)
      out.push(',\n')
    }
    for (const [k, item] of v.hash) {
      out.push(key(k), ' = ')
      write(item, out)
      out.push(',\n')
    }
    out.push('}')
  } else if (typeof v === 'string') out.push(quote(v))
  else if (typeof v === 'number') out.push(number(v))
  else if (typeof v === 'boolean') out.push(String(v))
  else out.push('nil')
}

// Map of global name -> value back to SavedVariables text, in WoW's layout
export function serialize(globals) {
  const out = []
  for (const [name, v] of globals) {
    out.push(name, ' = ')
    write(v, out)
    out.push('\n')
  }
  return out.join('')
}
