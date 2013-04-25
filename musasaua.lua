-- ----------------------------------------------------------------------------
-- "THE BEER-WARE LICENSE" (Revision 42):
-- <xxleite@gmail.com> wrote this file. As long as you retain this notice you
-- can do whatever you want with this stuff. If we meet some day, and you think
-- this stuff is worth it, you can buy me a beer in return
-- ----------------------------------------------------------------------------

-- YAHL, runs on top of luvit, the default http library breaks while i use coroutines
-- TODO: create write/reading semaphores

local string = require 'string'
local timer  = require 'timer'
local table  = require 'table'
local os     = require 'os'

-- libs methods
local musasaua, set_timeout, clear_timeout, find, gsub, match, lower, upper, sub, len, format, byte, time, date, insert, remove
    = {}, timer.setTimeout, timer.clearTimer, string.find, string.gsub, string.match, string.lower, string.upper, string.sub, string.len, string.format, string.byte, os.time, os.date, table.insert, table.remove

-- clean garbage
string, timer, table, os = nil, nil, nil, nil

-- local and private variables ...
local version, on_data, has_socket_events, timeout, connection, response, months      
    = 0.1, nil, false, nil, {socket=nil, domain='', port=0, headers={}, redirects=0, secure=false}, {code=0, headers=nil, data='', body=nil}, {Jan=1, Feb=2, Mar=3, Apr=4, May=5, Jun=6, Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12}

-- Local/Private methods ...

-- debug
local function debug(...)
  if musasaua.enable_debug then 
    p('musasaua: ', ...)
  end
end

-- parse gmt date string to unix date
local function get_unix_date(gmt_string)
  local D, M, Y, h, m, s = match(gmt_string, "%a+, ([^-]+)-([^-]+)-([^%s]+) ([^:]+):([^:]+):([^%s]+) %a+")
  return time({tz=0, day=D, month=months[M], year=Y, hour=h, min=m, sec=s})
end

-- convert unix date to gmt date string
local function get_gmt_string(unix_date)
  return date("!%a, %d-%b-%Y %H:%M:%S GMT", unix_date)
end

-- persists data upon navigation (cookie jar / referer)
local function persist_data(options)
  
  for k, v in pairs(options) do
    if v then
      if k=='cookie' then
        local xx, cookie_found = 0, false
        connection.headers[k] = connection.headers[k] or {}
        for xx=1, #connection.headers[k] do
          if connection.headers[k][xx].name==v.name and connection.headers[k][xx].domain==v.domain and connection.headers[k][xx].path==v.path then
            cookie_found = true
            if v.expires then
              if v.expires < time(date('!*t')) then
                remove(connection.headers[k], xx)
                xx = xx - 1
              else
                connection.headers[k][xx].value   = v.value
                connection.headers[k][xx].expires = v.expires
              end
            else
              connection.headers[k][xx].value   = v.value
              connection.headers[k][xx].expires = v.expires
            end
          end
        end

        if not cookie_found then
          insert(connection.headers[k], v)
        end
      else
        connection.headers[k] = v or connection.headers[k]
      end
    end
  end
end

-- pack all cookies array in cookie string according to the rules
local function pack_cookies(cookie_array, domain, path)
  local cookie, value = '', ''
  -- pack
  for xx=1, #cookie_array do
    debug('-- cookie --', cookie_array[xx].value)
    value = cookie_array[xx].value

    if cookie_array[xx].expires then
      value = cookie_array[xx].expires > time(date('!*t')) and value or nil
    end

    if cookie_array[xx].path and value then
      value = match(path, '^'..cookie_array[xx].path)~=nil and value or nil
    end

    if cookie_array[xx].domain and value then
      value = match(domain, cookie_array[xx].domain..'$')~=nil and value or nil
    end

    if value then
      cookie = format("%s; %s=%s", cookie, cookie_array[xx].name, value)
    end
  end
  return sub(cookie, 3)
end

-- parse response cookies
local function parse_cookie(string_cookie)
  local cookie = {}
  local function cookie_interator(k, v)
    --k = lower(k)
    if k=='expires' then
      v = get_unix_date(v)
    end
    if k~='expires' and k~='domain' and k~='path' then
      cookie.name  = k
      cookie.value = v
    else
      cookie[k] = v
    end
  end
  cookie.secure = find(string_cookie, '; Secure')~=nil
  gsub(string_cookie, "%s?([^=]*)=([^;?$?]*);?$?", cookie_interator)
  debug('-- cookie parsed --', cookie, string_cookie)
  return cookie
end

-- encode 
local function urlencode(str)
  if not str then
    return ''
  end
  return gsub(gsub(gsub(str, '\n', '\r\n'), '([^%w%_%.])', function(c) return format('%%%02X', byte(c)) end), ' ',  '+')
end

-- query table to query string
local function stringify_query(query_array)
  local query = ''
  if query_array then
    for key, value in pairs(query_array) do 
      query = format("%s&%s=%s", query, urlencode(key), urlencode(value))
    end
  end
  return sub(query, 2)
end

-- pack headers to request
local function pack_headers(header, domain, path)
  local http_header = ''
  for key, value in pairs(header) do
    if key=='cookie' then
      value = pack_cookies(value, domain, path)
    end
    http_header = http_header .. (len(value)>0 and "\r\n".. gsub(gsub(key, "^(%w)", upper), "(%-%w?)", upper) ..": ".. value or '')
  end
  return http_header
end

-- parse response headers
local function parse_headers()
  -- headers already parsed
  if response.code>0 then
    return true
  end   
  local headers_boundary, headers_content = find(response.data, "\r\n\r\n"), ''
  if not headers_boundary then 
    return false
  end
  headers_content = sub(response.data, 1, headers_boundary + 2)
  debug("<< " .. headers_content)
  
  -- while redirecting 
  if connection.redirects>0 then
    local old_headers = response.headers
    response.headers = {}
    for i=1, #old_headers do
      insert(response.headers, old_headers[i])
      old_headers[i] = nil
    end
    insert(response.headers, old_headers)
  else
    response.headers = {}
  end
  
  response.code    = tonumber(match(headers_content, "HTTP/%d%.%d (%d*) [^%c]"))
  gsub(headers_content, "%c%c?([^:]*):%s?([^%c]*)%c", function(k, v)
      k = lower(k)
      -- cookies logic
      if k=='set-cookie' then
        v = parse_cookie(v)
        persist_data({cookie = v})
      end

      if response.headers[k] then
        local old_header_item = response.headers[k]
        response.headers[k] = {}
        insert(response.headers[k], old_headers)
      else
        response.headers[k] = type(v)=='string' and (match(v, "^%d*$") and tonumber(v) or lower(v)) or v
      end
    end)
  response.data = sub(response.data, headers_boundary + 4, -1)
  return true
end

-- parse response body
local function parse_body()
  -- do not parse until contains headers
  if not response.headers then
    return false
  end
  -- already parsed
  if response.body~=nil then 
    return true
  end
  -- empty response eg.: proxy/CONNECT response or redirects
  if (not response.headers['content-length'] and not response.headers['transfer-encoding'] and not response.headers['content-type']) or
    response.code==302 or response.code==301 then
    return true
  end
  -- check content length ... 
  if response.headers['content-length'] then
    if len(response.data) < response.headers['content-length'] then 
      return false
    end
    response.body = sub(response.data, 1, response.headers['content-length'])
    response.data = ''
    return true
  end
  -- check transfer-encoding ...
  if response.headers['transfer-encoding']=='chunked' then
    -- do not parse until contains all body
    if sub(response.data, -5) ~= "0\r\n\r\n" then 
      return false
    end
    response.body = ''
    -- loop parser
    local size, offset = 0, 0
    while true do
      size   = find(response.data, "\r\n")
      offset = offset + size + 2
      size   = tonumber(sub(response.data, 1, size), 16)
      if size==0 then 
        break
      end
      response.body = response.body .. sub(response.data, offset, offset+size-1)
      response.data = sub(response.data, offset + size + 2, -1)
      offset        = 0
    end
    return true
  end
end

-- data receiving callback
local function on_receive(blob)
  if blob==false then
    clear_timeout(timeout)
    debug('-- receive timeout --')
    if connection.socket then
      connection.socket:destroy()
    end
    if on_data then
      set_timeout(3, on_data, false)
    end
    return
  end
  
  response.data = response.data .. blob
  --p(len(response.data))
  --debug('-- ... --', parse_headers(), parse_body())

  if parse_headers() and parse_body() then

    debug('-- HHH --', musasaua.follow_redirects, response.code)

    if musasaua.follow_redirects and (response.code==302 or response.code==301) then
      debug('-- about to redirecting --')
      if connection.redirects < musasaua.max_redirects then
        connection.redirects = connection.redirects + 1
        clear_timeout(timeout)
        --
        local function redirect_callback()

          debug('-- inside redirect callback ', connection)

          local url = gsub(response.headers.location, 'https?://'..connection.domain..'/', '/')
          debug('-- redirecting --', url)
          if sub(url, 1, 1)=='/' then
            musasaua:request({domain=connection.domain, port=connection.port, path=url}, nil)
          else
            musasaua:request({url=url}, nil)
          end
        end
        --
        if response.headers.connection=='close' then
          debug('-- about to close 0 --')
          connection.socket:destroy()
          connection.socket:once('close', redirect_callback)
        else
          redirect_callback()
        end
        return
      end
    end

    connection.redirects = 0

    if response.headers.connection=='close' then
      debug('-- about to close 1 --')
      connection.socket:destroy()
      return
    end

    clear_timeout(timeout)
    set_timeout(3, on_data, response)
    on_data = nil
  end
end

-- Public methods ...

-- main metatable
musasaua = setmetatable({

  connection_timeout = 10000,
  read_timeout       = 5000,
  keep_alive         = false,
  preserve_cookies   = true,
  follow_redirects   = true,
  max_redirects      = 2,
  enable_debug       = false,
  is_connected       = false,

  connect = function(self, host, port, secure, callback)
    -- already connected with the same host/port
    if connection.socket and (connection.domain==host and connection.port==port or self.keep_alive) then
      debug('-- already connected --')
      set_timeout(3, callback, nil)
      return
    end
    -- avoid mistakes
    if connection.socket then
      debug('-- destroys, connection is called twice --')
      connection.socket:destroy()
    end

    local _timeout
    local function on_completed(err)
      self.is_connected = true
      if err=='timeout' or type(err)=='table' then
        debug('-- destroys --', err)
        connection.socket:destroy()
        connection.socket = nil
        connection.domain = ''
        connection.port   = 0
      elseif type(err)=='function' then
        return
      else
        debug('-- clear connection timeout --')
        clear_timeout(_timeout)
      end
      callback(err)
    end

    connection.port   = port
    connection.domain = host
    connection.socket = (secure and require('tls').connect or require('net').createConnection)({host = host, port = port}, on_completed)
    _timeout = set_timeout(self.connection_timeout, on_completed, 'timeout')

    if not has_socket_events then
      debug('-- assign events --')
      --connection.socket:on('drain', function(a) p('drain', a) end)
      --connection.socket:on('end', function(a) p('end', a) end)
      connection.socket:on('error', on_completed)
      connection.socket:on('close', function() 
        debug('-- closed --')
        self.is_connected = false
        if connection.redirects==0 then
          connection.domain = ''
          connection.port   = 0
          debug('-- inside close --', on_data)
          if on_data then
            debug('-- socket closed, calling callback --')
            if timeout then
              debug('-- timeout after closed --', timeout)
              clear_timeout(timeout)
            end
            set_timeout(3, on_data, response)
          end
          on_data = nil
        end
        connection.socket = nil
        has_socket_events = false
      end)

      connection.socket:on('data', on_receive)

      has_socket_events = true
    end
  end,

  -- options, callback
  -- options = {url = '', params = {}, method = 'GET', headers = {}, timeout = 20000}
  request = function(self, options, callback)
    --if not options.url then
    --  set_timeout(3, callback or on_data, 'url is mandatory')
    --  return
    --end
    options.params  = options.params  or ''
    options.method  = options.method  or 'GET'
    options.headers = options.headers or {}
    options.timeout = options.timeout or self.read_timeout

    local headers, use_ssl = {}, false

    if not options.domain or not options.port then
      local function parse_domain(protocol, domain_name, port_number, path_string)
        if protocol=="https" then
          options.port = tonumber(port_number) or 443
          use_ssl      = true
        elseif protocol=="http" then
          options.port = tonumber(port_number) or 80
          use_ssl      = false
        else
          error('Invalid protocol')
        end
        options.domain = domain_name 
        options.path   = options.path or path_string
      end

      gsub(options.url, "^(https?)://([^:?/]*):?(%d*)(/[^$]*)$", parse_domain)
    else
      use_ssl = use_ssl and use_ssl or (options.port==443 and true or false)
    end

    -- sanitize headers
    for key, value in pairs(connection.headers) do
      headers[lower(key)] = value
    end
    for key, value in pairs(options.headers) do
      headers[lower(key)] = value
    end
    headers['user-agent'] = format("Lua-Musasaua/%g", version)
    headers.connection    = headers.connection or (self.keep_alive and 'keep-alive' or 'close')
    headers.accept        = headers.accept or '*/*'
    headers.host          = headers.host or (options.domain .. ((options.port==80 or options.port==443) and '' or ':'..options.port))
    options.headers       = headers

    local function on_connected(err)
      if err then
        debug('-- whathahell --', err)
        set_timeout(3, callback or on_data, err)
        return
      end

      local to_send = ''

      if options.method=='GET' or options.method=='HEAD' then
        local search = (type(options.params)=='string' and options.params or stringify_query(options.params))
        options.path = options.path .. (search=='' and '' or '?'..search)
        to_send = format("%s %s HTTP/1.1%s\r\n\r\n", options.method, options.path, pack_headers(options.headers, options.domain, options.path))
        connection.socket:write(to_send)
      elseif options.method=='POST' or options.method=='PUT' then
        options.params = (type(options.params)=='string' and options.params or stringify_query(options.params))
        options.headers['content-length'] = len(options.params)
        options.headers['content-type']   = 'application/x-www-form-urlencoded'
        to_send = format("%s %s HTTP/1.1%s\r\n\r\n%s\r\n\r\n", options.method, options.path, pack_headers(options.headers, options.domain, options.path), options.params)
        connection.socket:write(to_send)
      elseif options.method=='CONNECT' then
        to_send = format("CONNECT %s HTTP/1.0\nHost: %s\nLua-Musasaua/%g\n\n", options.url, options.url, version)
        connection.socket:write(to_send)
      else
        error('Invalid request method')
      end

      debug('-- connected --')
      debug('>> '.. to_send)

      persist_data({
        referer       = options.url or ((options.path and options.headers.referer) and gsub(options.headers.referer, "(https?://[^/?$?]+)/?([^$]*)", "%1"..options.path) or options.headers.referer), 
        authorization = options.headers.authorization
      })

      if response.headers then
        if not response.headers.location then
          response.headers = nil
        end
      else
        response.headers = nil
      end
      response.code    = 0
      response.data    = ''
      response.body    = nil

      debug(on_data, callback)

      on_data          = callback or on_data
      timeout          = set_timeout(options.timeout, on_receive, false)
    end

    debug(format("%s:%d, %s", options.domain, options.port, use_ssl and 'secure socket layer' or 'ok'))
    self:connect(options.domain, options.port, use_ssl, on_connected)
  end

},{__index = musasaua})

return musasaua